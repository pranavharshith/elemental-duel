// Elemental Duel room relay.
//
// How a match connects (Smash Karts / skribbl style):
//   1. The host opens   wss://<server>/host?v=<version>
//      -> the Worker picks a free 5-letter room code and hands the socket to
//         that room's Durable Object, which replies {"t":"welcome","code":...}.
//   2. The friend opens wss://<server>/join/<CODE>?v=<version>
//      -> same Durable Object; the host gets {"t":"peer_joined"}.
//   3. From then on every BINARY frame from one player is forwarded to the
//      other unchanged (Godot's multiplayer packets). TEXT frames are control
//      messages ("ping" is answered automatically with "pong").
//
// The relay never interprets game data; the host's game is authoritative.
// Only 2 players per room. A room disappears when the host leaves.

import { DurableObject } from "cloudflare:workers";

const GAME_VERSION = "elemental-duel-net-2";
// No 0/O/1/I so codes are easy to read aloud and type.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
const CODE_LENGTH = 5;
const CODE_PATTERN = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{5}$/;
const MAX_FRAME_BYTES = 64 * 1024;
const CREATE_ATTEMPTS = 8;

type Role = "host" | "join";

interface Env {
	ROOMS: DurableObjectNamespace<Room>;
	// Optional Cloudflare Realtime TURN key (secrets). When set, /ice also
	// returns short-lived TURN credentials so players behind strict NATs still
	// get a low-latency WebRTC path via Cloudflare's nearest edge instead of
	// falling back to the room relay.
	TURN_KEY_ID?: string;
	TURN_KEY_API_TOKEN?: string;
}

const STUN_ONLY = [{ urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"] }];
const TURN_TTL_SECONDS = 4 * 60 * 60;
const CORS = { "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store" };

/** ICE servers for the game's direct (WebRTC) link. */
async function iceServers(env: Env): Promise<Response> {
	if (env.TURN_KEY_ID && env.TURN_KEY_API_TOKEN) {
		try {
			const res = await fetch(
				`https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`,
				{
					method: "POST",
					headers: { Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`, "Content-Type": "application/json" },
					body: JSON.stringify({ ttl: TURN_TTL_SECONDS }),
				},
			);
			if (res.ok) {
				const data = (await res.json()) as { iceServers?: unknown };
				if (Array.isArray(data.iceServers) && data.iceServers.length > 0) {
					return Response.json({ iceServers: data.iceServers }, { headers: CORS });
				}
			}
			console.error(JSON.stringify({ msg: "turn credentials failed", status: res.status }));
		} catch (err) {
			console.error(JSON.stringify({ msg: "turn credentials error", error: String(err) }));
		}
	}
	return Response.json({ iceServers: STUN_ONLY }, { headers: CORS });
}

function randomCode(): string {
	const bytes = new Uint8Array(CODE_LENGTH);
	crypto.getRandomValues(bytes);
	let code = "";
	for (const b of bytes) code += CODE_ALPHABET[b & 31];
	return code;
}

/**
 * Accept the WebSocket, send an error the game can show, then close.
 * (An HTTP error status would reach Godot only as "connection failed".)
 */
function socketError(message: string, closeCode = 4001): Response {
	const pair = new WebSocketPair();
	const [client, server] = Object.values(pair);
	server.accept();
	server.send(JSON.stringify({ t: "error", msg: message }));
	server.close(closeCode, message.slice(0, 120));
	return new Response(null, { status: 101, webSocket: client });
}

function roomRequest(request: Request, role: Role, code: string): Request {
	const headers = new Headers(request.headers);
	headers.set("X-Relay-Role", role);
	headers.set("X-Relay-Code", code);
	return new Request(request.url, { method: "GET", headers });
}

export default {
	async fetch(request: Request, env: Env): Promise<Response> {
		const url = new URL(request.url);
		if (url.pathname === "/" || url.pathname === "/health") {
			return Response.json({ ok: true, game: GAME_VERSION });
		}
		if (url.pathname === "/ice") {
			return iceServers(env);
		}
		if (request.headers.get("Upgrade")?.toLowerCase() !== "websocket") {
			return new Response("Expected a WebSocket upgrade", { status: 426 });
		}
		if (url.searchParams.get("v") !== GAME_VERSION) {
			return socketError("Your game is a different version than the server. Update the game.");
		}
		try {
			if (url.pathname === "/host") {
				for (let i = 0; i < CREATE_ATTEMPTS; i++) {
					const code = randomCode();
					const res = await env.ROOMS.getByName(code).fetch(roomRequest(request, "host", code));
					if (res.status === 101) return res;
				}
				return socketError("The server is busy. Try again.");
			}
			const join = url.pathname.match(/^\/join\/([A-Za-z0-9]+)$/);
			if (join) {
				const code = join[1].toUpperCase();
				if (!CODE_PATTERN.test(code)) {
					return socketError("Room not found. Check the code.");
				}
				return await env.ROOMS.getByName(code).fetch(roomRequest(request, "join", code));
			}
		} catch (err) {
			console.error(JSON.stringify({ msg: "relay fetch failed", error: String(err) }));
			return socketError("Server error. Try again.");
		}
		return new Response("Not found", { status: 404 });
	},
} satisfies ExportedHandler<Env>;

/** One room = one Durable Object, holding at most a host socket and a joiner socket. */
export class Room extends DurableObject<Env> {
	constructor(ctx: DurableObjectState, env: Env) {
		super(ctx, env);
		// Keep-alive pings are answered without waking the object (not billed).
		this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
	}

	private open(role: Role): WebSocket[] {
		return this.ctx.getWebSockets(role).filter((ws) => ws.readyState === WebSocket.OPEN);
	}

	private static roleOf(ws: WebSocket): Role {
		return (ws.deserializeAttachment() as { role: Role } | null)?.role ?? "join";
	}

	private accept(role: Role, code: string): Response {
		const pair = new WebSocketPair();
		const [client, server] = Object.values(pair);
		this.ctx.acceptWebSocket(server, [role]);
		server.serializeAttachment({ role });
		server.send(JSON.stringify({ t: "welcome", role, code, id: role === "host" ? 1 : 2 }));
		return new Response(null, { status: 101, webSocket: client });
	}

	async fetch(request: Request): Promise<Response> {
		const role = request.headers.get("X-Relay-Role") as Role | null;
		const code = request.headers.get("X-Relay-Code") ?? "";
		if (role === "host") {
			// Code already in use: tell the Worker to pick another one.
			if (this.open("host").length > 0 || this.open("join").length > 0) {
				return new Response("taken", { status: 409 });
			}
			return this.accept("host", code);
		}
		if (role === "join") {
			const hosts = this.open("host");
			if (hosts.length === 0) return socketError("Room not found. Check the code, or ask your friend to create a new room.");
			if (this.open("join").length > 0) return socketError("That room is already full.");
			const res = this.accept("join", code);
			for (const h of hosts) h.send(JSON.stringify({ t: "peer_joined" }));
			return res;
		}
		return new Response("Bad request", { status: 400 });
	}

	async webSocketMessage(ws: WebSocket, message: ArrayBuffer | string): Promise<void> {
		const role = Room.roleOf(ws);
		if (typeof message === "string") {
			// The host can remove the joiner (e.g. wrong game version).
			if (message === "kick" && role === "host") {
				for (const j of this.open("join")) {
					j.send(JSON.stringify({ t: "error", msg: "The host removed you from the room." }));
					j.close(4002, "Removed by host");
				}
				for (const h of this.open("host")) h.send(JSON.stringify({ t: "peer_left" }));
			}
			return;
		}
		if (message.byteLength > MAX_FRAME_BYTES) return;
		for (const other of this.open(role === "host" ? "join" : "host")) {
			if (other !== ws) other.send(message);
		}
	}

	async webSocketClose(ws: WebSocket, code: number, reason: string): Promise<void> {
		this.left(ws);
		try {
			ws.close(code === 1005 || code === 1006 ? 1000 : code, reason);
		} catch {
			// Already closed.
		}
	}

	async webSocketError(ws: WebSocket): Promise<void> {
		this.left(ws);
	}

	private left(ws: WebSocket): void {
		if (Room.roleOf(ws) === "host") {
			for (const j of this.open("join")) {
				if (j === ws) continue;
				j.send(JSON.stringify({ t: "error", msg: "The host left the room." }));
				j.close(4000, "Host left");
			}
		} else {
			for (const h of this.open("host")) {
				if (h !== ws) h.send(JSON.stringify({ t: "peer_left" }));
			}
		}
	}
}
