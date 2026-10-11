var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// src/index.ts
import { DurableObject } from "cloudflare:workers";
var GAME_VERSION = "elemental-duel-net-2";
var CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
var CODE_LENGTH = 5;
var CODE_PATTERN = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{5}$/;
var MAX_FRAME_BYTES = 64 * 1024;
var CREATE_ATTEMPTS = 8;
var STUN_ONLY = [{ urls: ["stun:stun.cloudflare.com:3478", "stun:stun.l.google.com:19302"] }];
var TURN_TTL_SECONDS = 4 * 60 * 60;
var CORS = { "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store" };
async function iceServers(env) {
  if (env.TURN_KEY_ID && env.TURN_KEY_API_TOKEN) {
    try {
      const res = await fetch(
        `https://rtc.live.cloudflare.com/v1/turn/keys/${env.TURN_KEY_ID}/credentials/generate-ice-servers`,
        {
          method: "POST",
          headers: { Authorization: `Bearer ${env.TURN_KEY_API_TOKEN}`, "Content-Type": "application/json" },
          body: JSON.stringify({ ttl: TURN_TTL_SECONDS })
        }
      );
      if (res.ok) {
        const data = await res.json();
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
__name(iceServers, "iceServers");
function randomCode() {
  const bytes = new Uint8Array(CODE_LENGTH);
  crypto.getRandomValues(bytes);
  let code = "";
  for (const b of bytes) code += CODE_ALPHABET[b & 31];
  return code;
}
__name(randomCode, "randomCode");
function socketError(message, closeCode = 4001) {
  const pair = new WebSocketPair();
  const [client, server] = Object.values(pair);
  server.accept();
  server.send(JSON.stringify({ t: "error", msg: message }));
  server.close(closeCode, message.slice(0, 120));
  return new Response(null, { status: 101, webSocket: client });
}
__name(socketError, "socketError");
function roomRequest(request, role, code) {
  const headers = new Headers(request.headers);
  headers.set("X-Relay-Role", role);
  headers.set("X-Relay-Code", code);
  return new Request(request.url, { method: "GET", headers });
}
__name(roomRequest, "roomRequest");
var src_default = {
  async fetch(request, env) {
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
  }
};
var Room = class _Room extends DurableObject {
  static {
    __name(this, "Room");
  }
  constructor(ctx, env) {
    super(ctx, env);
    this.ctx.setWebSocketAutoResponse(new WebSocketRequestResponsePair("ping", "pong"));
  }
  open(role) {
    return this.ctx.getWebSockets(role).filter((ws) => ws.readyState === WebSocket.OPEN);
  }
  static roleOf(ws) {
    return ws.deserializeAttachment()?.role ?? "join";
  }
  accept(role, code) {
    const pair = new WebSocketPair();
    const [client, server] = Object.values(pair);
    this.ctx.acceptWebSocket(server, [role]);
    server.serializeAttachment({ role });
    server.send(JSON.stringify({ t: "welcome", role, code, id: role === "host" ? 1 : 2 }));
    return new Response(null, { status: 101, webSocket: client });
  }
  async fetch(request) {
    const role = request.headers.get("X-Relay-Role");
    const code = request.headers.get("X-Relay-Code") ?? "";
    if (role === "host") {
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
  async webSocketMessage(ws, message) {
    const role = _Room.roleOf(ws);
    if (typeof message === "string") {
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
  async webSocketClose(ws, code, reason) {
    this.left(ws);
    try {
      ws.close(code === 1005 || code === 1006 ? 1e3 : code, reason);
    } catch {
    }
  }
  async webSocketError(ws) {
    this.left(ws);
  }
  left(ws) {
    if (_Room.roleOf(ws) === "host") {
      for (const j of this.open("join")) {
        if (j === ws) continue;
        j.send(JSON.stringify({ t: "error", msg: "The host left the room." }));
        j.close(4e3, "Host left");
      }
    } else {
      for (const h of this.open("host")) {
        if (h !== ws) h.send(JSON.stringify({ t: "peer_left" }));
      }
    }
  }
};

// node_modules/wrangler/templates/middleware/middleware-ensure-req-body-drained.ts
var drainBody = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } finally {
    try {
      if (request.body !== null && !request.bodyUsed) {
        const reader = request.body.getReader();
        while (!(await reader.read()).done) {
        }
      }
    } catch (e) {
      console.error("Failed to drain the unused request body.", e);
    }
  }
}, "drainBody");
var middleware_ensure_req_body_drained_default = drainBody;

// node_modules/wrangler/templates/middleware/middleware-miniflare3-json-error.ts
function reduceError(e) {
  return {
    name: e?.name,
    message: e?.message ?? String(e),
    stack: e?.stack,
    cause: e?.cause === void 0 ? void 0 : reduceError(e.cause)
  };
}
__name(reduceError, "reduceError");
var jsonError = /* @__PURE__ */ __name(async (request, env, _ctx, middlewareCtx) => {
  try {
    return await middlewareCtx.next(request, env);
  } catch (e) {
    const error = reduceError(e);
    const body = JSON.stringify(error);
    const headers = {
      "Content-Type": "application/json",
      "MF-Experimental-Error-Stack": "true"
    };
    const encoded = encodeURIComponent(body);
    if (encoded.length <= 8192) {
      headers["MF-Experimental-Error-Stack-Payload"] = encoded;
    }
    return new Response(body, { status: 500, headers });
  }
}, "jsonError");
var middleware_miniflare3_json_error_default = jsonError;

// .wrangler/tmp/bundle-AgQYWA/middleware-insertion-facade.js
var __INTERNAL_WRANGLER_MIDDLEWARE__ = [
  middleware_ensure_req_body_drained_default,
  middleware_miniflare3_json_error_default
];
var middleware_insertion_facade_default = src_default;

// node_modules/wrangler/templates/middleware/common.ts
var __facade_middleware__ = [];
function __facade_register__(...args) {
  __facade_middleware__.push(...args.flat());
}
__name(__facade_register__, "__facade_register__");
function __facade_invokeChain__(request, env, ctx, dispatch, middlewareChain) {
  const [head, ...tail] = middlewareChain;
  const middlewareCtx = {
    dispatch,
    next(newRequest, newEnv) {
      return __facade_invokeChain__(newRequest, newEnv, ctx, dispatch, tail);
    }
  };
  return head(request, env, ctx, middlewareCtx);
}
__name(__facade_invokeChain__, "__facade_invokeChain__");
function __facade_invoke__(request, env, ctx, dispatch, finalMiddleware) {
  return __facade_invokeChain__(request, env, ctx, dispatch, [
    ...__facade_middleware__,
    finalMiddleware
  ]);
}
__name(__facade_invoke__, "__facade_invoke__");

// .wrangler/tmp/bundle-AgQYWA/middleware-loader.entry.ts
var __Facade_ScheduledController__ = class ___Facade_ScheduledController__ {
  constructor(scheduledTime, cron, noRetry) {
    this.scheduledTime = scheduledTime;
    this.cron = cron;
    this.#noRetry = noRetry;
  }
  scheduledTime;
  cron;
  static {
    __name(this, "__Facade_ScheduledController__");
  }
  #noRetry;
  noRetry() {
    if (!(this instanceof ___Facade_ScheduledController__)) {
      throw new TypeError("Illegal invocation");
    }
    this.#noRetry();
  }
};
function wrapExportedHandler(worker) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return worker;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  const fetchDispatcher = /* @__PURE__ */ __name(function(request, env, ctx) {
    if (worker.fetch === void 0) {
      throw new Error("Handler does not export a fetch() function.");
    }
    return worker.fetch(request, env, ctx);
  }, "fetchDispatcher");
  return {
    ...worker,
    fetch(request, env, ctx) {
      const dispatcher = /* @__PURE__ */ __name(function(type, init) {
        if (type === "scheduled" && worker.scheduled !== void 0) {
          const controller = new __Facade_ScheduledController__(
            Date.now(),
            init.cron ?? "",
            () => {
            }
          );
          return worker.scheduled(controller, env, ctx);
        }
      }, "dispatcher");
      return __facade_invoke__(request, env, ctx, dispatcher, fetchDispatcher);
    }
  };
}
__name(wrapExportedHandler, "wrapExportedHandler");
function wrapWorkerEntrypoint(klass) {
  if (__INTERNAL_WRANGLER_MIDDLEWARE__ === void 0 || __INTERNAL_WRANGLER_MIDDLEWARE__.length === 0) {
    return klass;
  }
  for (const middleware of __INTERNAL_WRANGLER_MIDDLEWARE__) {
    __facade_register__(middleware);
  }
  return class extends klass {
    #fetchDispatcher = /* @__PURE__ */ __name((request, env, ctx) => {
      this.env = env;
      this.ctx = ctx;
      if (super.fetch === void 0) {
        throw new Error("Entrypoint class does not define a fetch() function.");
      }
      return super.fetch(request);
    }, "#fetchDispatcher");
    #dispatcher = /* @__PURE__ */ __name((type, init) => {
      if (type === "scheduled" && super.scheduled !== void 0) {
        const controller = new __Facade_ScheduledController__(
          Date.now(),
          init.cron ?? "",
          () => {
          }
        );
        return super.scheduled(controller);
      }
    }, "#dispatcher");
    fetch(request) {
      return __facade_invoke__(
        request,
        this.env,
        this.ctx,
        this.#dispatcher,
        this.#fetchDispatcher
      );
    }
  };
}
__name(wrapWorkerEntrypoint, "wrapWorkerEntrypoint");
var WRAPPED_ENTRY;
if (typeof middleware_insertion_facade_default === "object") {
  WRAPPED_ENTRY = wrapExportedHandler(middleware_insertion_facade_default);
} else if (typeof middleware_insertion_facade_default === "function") {
  WRAPPED_ENTRY = wrapWorkerEntrypoint(middleware_insertion_facade_default);
}
var middleware_loader_entry_default = WRAPPED_ENTRY;
export {
  Room,
  __INTERNAL_WRANGLER_MIDDLEWARE__,
  middleware_loader_entry_default as default
};
//# sourceMappingURL=index.js.map
