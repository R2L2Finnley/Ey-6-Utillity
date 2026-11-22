/* Web-Bluetooth-Brücke für iOS.
   iOS-WebViews kennen navigator.bluetooth nicht. Dieses Skript stellt die
   Teile der API nach, die EY6 Control benutzt, und leitet sie an CoreBluetooth
   (BLEBridge.swift) weiter. Die HTML-Seite selbst bleibt unverändert. */
(() => {
  if (window.__eyBridge) return;
  window.__eyBridge = true;

  const H = window.webkit.messageHandlers.ble;
  let seq = 0;
  const pending = new Map();

  const call = (cmd, args) => new Promise((resolve, reject) => {
    const id = ++seq;
    pending.set(id, { resolve, reject });
    H.postMessage(Object.assign({ id, cmd }, args || {}));
  });
  const fire = (cmd, args) => H.postMessage(Object.assign({ cmd }, args || {}));

  window.__eyReply = (id, ok, payload) => {
    const p = pending.get(id);
    if (!p) return;
    pending.delete(id);
    if (ok) p.resolve(payload);
    else p.reject(new DOMException((payload && payload.message) || "Fehler", (payload && payload.name) || "NetworkError"));
  };

  /* ---------- Hilfen ---------- */

  const hex16 = n => n.toString(16).padStart(4, "0");
  const SVC = { generic_access: 0x1800, generic_attribute: 0x1801, device_information: 0x180a, battery_service: 0x180f };
  const CHR = {
    battery_level: 0x2a19, manufacturer_name_string: 0x2a29, model_number_string: 0x2a24,
    serial_number_string: 0x2a25, hardware_revision_string: 0x2a27,
    firmware_revision_string: 0x2a26, software_revision_string: 0x2a28
  };
  function toUuid(x, table) {
    if (typeof x === "number") return hex16(x);
    x = String(x).toLowerCase();
    if (table[x] !== undefined) return hex16(table[x]);
    const m = x.match(/^0000([0-9a-f]{4})-0000-1000-8000-00805f9b34fb$/);
    return m ? m[1] : x;
  }

  function b64(src) {
    const u8 = src instanceof ArrayBuffer ? new Uint8Array(src) : new Uint8Array(src.buffer, src.byteOffset, src.byteLength);
    let s = "";
    for (let i = 0; i < u8.length; i += 0x8000) s += String.fromCharCode.apply(null, u8.subarray(i, i + 0x8000));
    return btoa(s);
  }
  function view(b) {
    const s = atob(b || "");
    const u8 = new Uint8Array(s.length);
    for (let i = 0; i < s.length; i++) u8[i] = s.charCodeAt(i);
    return new DataView(u8.buffer);
  }

  const devices = new Map();
  const chars = new Map();

  /* ---------- GATT-Objekte ---------- */

  class Characteristic extends EventTarget {
    constructor(service, uuid, props) {
      super();
      this.service = service;
      this.uuid = uuid;
      this.properties = props || {};
      this.value = null;
    }
    get _a() { return { dev: this.service.device.id, svc: this.service.uuid, chr: this.uuid }; }
    async readValue() {
      const r = await call("read", this._a);
      this.value = view(r.value);
      return this.value;
    }
    async writeValueWithResponse(v) { await call("write", Object.assign({ value: b64(v) }, this._a)); }
    async writeValueWithoutResponse(v) { await call("writeNoResponse", Object.assign({ value: b64(v) }, this._a)); }
    async writeValue(v) {
      return this.properties.write ? this.writeValueWithResponse(v) : this.writeValueWithoutResponse(v);
    }
    async startNotifications() { await call("notify", Object.assign({ on: true }, this._a)); return this; }
    async stopNotifications() { await call("notify", Object.assign({ on: false }, this._a)); return this; }
  }

  class Service {
    constructor(device, uuid) { this.device = device; this.uuid = uuid; this.isPrimary = true; }
    async getCharacteristic(name) {
      const u = toUuid(name, CHR);
      const key = this.device.id + "|" + this.uuid + "|" + u;
      if (chars.has(key)) return chars.get(key);
      const props = await call("characteristic", { dev: this.device.id, svc: this.uuid, chr: u });
      const c = new Characteristic(this, u, props);
      chars.set(key, c);
      return c;
    }
  }

  class Gatt {
    constructor(device) { this.device = device; this._connected = false; }
    get connected() { return this._connected; }
    async connect() {
      await call("connect", { dev: this.device.id });
      this._connected = true;
      return this;
    }
    disconnect() { fire("disconnect", { id: ++seq, dev: this.device.id }); }
    async getPrimaryService(name) {
      const u = toUuid(name, SVC);
      await call("service", { dev: this.device.id, svc: u });
      return new Service(this.device, u);
    }
  }

  class Device extends EventTarget {
    constructor(id, name) {
      super();
      this.id = id;
      this.name = name || null;
      this.gatt = new Gatt(this);
      this.watchingAdvertisements = false;
    }
    async watchAdvertisements(opts) {
      const sig = opts && opts.signal;
      if (sig && sig.aborted) throw new DOMException("Abgebrochen", "AbortError");
      await call("watch", { dev: this.id });
      this.watchingAdvertisements = true;
      if (sig) sig.addEventListener("abort", () => {
        this.watchingAdvertisements = false;
        fire("unwatch", { id: ++seq, dev: this.id });
      });
    }
    async forget() {
      await call("forget", { dev: this.id });
      devices.delete(this.id);
    }
  }

  function deviceFor(info) {
    let d = devices.get(info.id);
    if (!d) { d = new Device(info.id, info.name); devices.set(info.id, d); }
    else if (info.name) d.name = info.name;
    return d;
  }

  /* ---------- Ereignisse von iOS ---------- */

  window.__eyEvent = (type, e) => {
    const d = devices.get(e.dev);
    if (type === "value") {
      const c = chars.get(e.dev + "|" + e.svc + "|" + e.chr);
      if (c) { c.value = view(e.value); c.dispatchEvent(new Event("characteristicvaluechanged")); }
    } else if (type === "disconnected") {
      for (const k of Array.from(chars.keys())) if (k.startsWith(e.dev + "|")) chars.delete(k);
      if (d && d.gatt._connected) {
        d.gatt._connected = false;
        d.dispatchEvent(new Event("gattserverdisconnected"));
      }
    } else if (type === "adv") {
      if (d) { d.watchingAdvertisements = false; d.dispatchEvent(new Event("advertisementreceived")); }
    }
  };

  /* ---------- navigator.bluetooth ---------- */

  const bluetooth = {
    async requestDevice() { return deviceFor(await call("requestDevice")); },
    async getDevices() { return (await call("getDevices")).map(deviceFor); },
    async getAvailability() { return true; }
  };
  try { Object.defineProperty(navigator, "bluetooth", { value: bluetooth, configurable: true }); } catch (e) {}

  /* ---------- localStorage (dauerhaft über UserDefaults) ---------- */

  try {
    const mem = Object.assign({}, window.__nativeStore || {});
    const shim = {
      getItem: k => (k in mem ? mem[k] : null),
      setItem: (k, v) => { mem[k] = String(v); fire("store", { op: "set", key: k, value: String(v) }); },
      removeItem: k => { delete mem[k]; fire("store", { op: "del", key: k }); },
      clear: () => { for (const k in mem) delete mem[k]; fire("store", { op: "clear" }); },
      key: i => Object.keys(mem)[i] || null,
      get length() { return Object.keys(mem).length; }
    };
    Object.defineProperty(window, "localStorage", { value: shim, configurable: true });
  } catch (e) {}

  /* ---------- Zwischenablage und Speichern (Teilen-Menü) ---------- */

  try {
    Object.defineProperty(navigator, "clipboard", {
      value: { writeText: t => call("copy", { text: String(t) }) },
      configurable: true
    });
  } catch (e) {}

  const blobs = new Map();
  const origCreate = URL.createObjectURL;
  URL.createObjectURL = function (b) { const u = origCreate.call(URL, b); blobs.set(u, b); return u; };
  const origClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    const b = this.download && blobs.get(this.href);
    if (b) {
      b.text().then(t => call("share", { name: this.download, text: t })).catch(() => {});
      return;
    }
    return origClick.call(this);
  };
})();
