/*
 * Adapted from shell/plugins/panels/tailscale/Model.js in Omarchy:
 * https://github.com/basecamp/omarchy/blob/b15ec6c6b3bac1e0406608f4a130f1684e734088/shell/plugins/panels/tailscale/Model.js
 * commit b15ec6c6b3bac1e0406608f4a130f1684e734088, MIT.
 * Hardened for standalone use.
 */

var MAX_INPUT = 2 * 1024 * 1024;
var MAX_DISPLAY = 80;
var MAX_LONG_DISPLAY = 120;
var MAX_AUTH_URL = 2048;
var MAX_PEERS = 200;
var MAX_ACCOUNTS = 32;
var MAX_EXIT_ROWS = 256;
var MAX_REGIONS = 128;
var MAX_TAGS = 32;
var FILE_SHARING_CAPABILITY = "https://tailscale.com/cap/file-sharing";
var hasOwnProperty = Object.prototype.hasOwnProperty;

function asString(value) {
  if (value === null || value === undefined) return "";
  return String(value);
}

function sanitizeDisplay(value, maxLen) {
  if (value === null || value === undefined) return "";
  if (typeof value !== "string" && typeof value !== "number" && typeof value !== "boolean") return "";

  var text = String(value);
  text = text.replace(/[\u0000-\u001F\u007F-\u009F\u00AD\u061C\u200B-\u200F\u2028\u2029\u202A-\u202E\u2060-\u206F\uFEFF]/g, " ");
  text = text.replace(/\s+/g, " ").trim();

  if (typeof maxLen === "number" && maxLen > 0 && text.length > maxLen) {
    text = text.slice(0, maxLen);
  }
  return text;
}

function rawText(value) {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  return String(value);
}

function boundedText(value) {
  var text = rawText(value);
  if (text.length > MAX_INPUT) return null;
  return text;
}

function normalizeOpaqueId(value) {
  var text = sanitizeDisplay(value, MAX_LONG_DISPLAY);
  if (text === "" || text.length > MAX_LONG_DISPLAY) return "";
  if (!/^[A-Za-z0-9][A-Za-z0-9._:+\/=\-@]{0,119}$/.test(text)) return "";
  return text;
}

function slugPart(value) {
  var text = sanitizeDisplay(value, MAX_DISPLAY).toLowerCase();
  text = text.replace(/[^a-z0-9]+/g, "-");
  text = text.replace(/^-+/, "").replace(/-+$/, "");
  return text;
}

function opaqueIdFromParts(prefix, first, second) {
  var id = String(prefix || "id");
  var part = slugPart(first);
  if (part !== "") id += ":" + part;
  part = slugPart(second);
  if (part !== "") id += ":" + part;
  if (id.length > MAX_LONG_DISPLAY) id = id.slice(0, MAX_LONG_DISPLAY).replace(/[:\-.]+$/, "");
  return normalizeOpaqueId(id) || normalizeOpaqueId(String(prefix || "id")) || "id";
}

function cleanDnsName(name) {
  var value = sanitizeDisplay(name, MAX_LONG_DISPLAY).toLowerCase();
  if (value.charAt(value.length - 1) === ".") value = value.slice(0, -1);
  if (value === "" || value.length > 253) return "";

  var labels = value.split(".");
  for (var i = 0; i < labels.length; i++) {
    var label = labels[i];
    if (label === "" || label.length > 63) return "";
    if (!/^[a-z0-9-]+$/.test(label)) return "";
    if (label.charAt(0) === "-" || label.charAt(label.length - 1) === "-") return "";
  }
  return labels.join(".");
}

function shortDnsName(name) {
  var clean = cleanDnsName(name);
  if (clean === "") return "";
  return clean.split(".")[0] || clean;
}

function displayHostName(hostName, dnsName) {
  var host = sanitizeDisplay(hostName, MAX_DISPLAY);
  if (host !== "" && host.toLowerCase() !== "localhost") return host;
  return shortDnsName(dnsName) || host || "Unknown";
}

function normalizeTailnetIPv4(value) {
  var text = sanitizeDisplay(value, 64);
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(text)) return "";

  var parts = text.split(".");
  var numbers = [];
  for (var i = 0; i < 4; i++) {
    var part = parts[i];
    if (part === "") return "";
    var number = Number(part);
    if (!isFinite(number) || number < 0 || number > 255 || Math.floor(number) !== number) return "";
    numbers.push(number);
  }

  if (numbers[0] !== 100) return "";
  if (numbers[1] < 64 || numbers[1] > 127) return "";
  return numbers.join(".");
}

function expandIPv6(text) {
  if (text === "" || /[^0-9a-f:]/i.test(text)) return null;
  if (/:::/.test(text)) return null;
  if (text.indexOf(".") !== -1) return null;

  var halves = text.split("::");
  if (halves.length > 2) return null;

  var left = halves[0] === "" ? [] : halves[0].split(":");
  var right = halves.length === 2 ? (halves[1] === "" ? [] : halves[1].split(":")) : [];
  var groups = [];
  var index;

  for (index = 0; index < left.length; index++) {
    if (!/^[0-9a-f]{1,4}$/i.test(left[index])) return null;
    groups.push(parseInt(left[index], 16));
  }

  if (halves.length === 1) {
    if (groups.length !== 8) return null;
  } else {
    var total = left.length + right.length;
    if (total >= 8) return null;
    for (index = 0; index < 8 - total; index++) groups.push(0);
  }

  for (index = 0; index < right.length; index++) {
    if (!/^[0-9a-f]{1,4}$/i.test(right[index])) return null;
    groups.push(parseInt(right[index], 16));
  }

  if (groups.length !== 8) return null;
  return groups;
}

function normalizeTailnetIPv6(value) {
  var text = sanitizeDisplay(value, MAX_LONG_DISPLAY).toLowerCase();
  var groups = expandIPv6(text);
  if (!groups) return "";
  if (groups[0] !== 0xfd7a || groups[1] !== 0x115c || groups[2] !== 0xa1e0) return "";

  var result = [];
  for (var i = 0; i < groups.length; i++) result.push(groups[i].toString(16));
  return result.join(":");
}

function filterIPv4(ips) {
  var result = [];
  var seen = {};
  if (!ips || typeof ips.length !== "number") return result;

  for (var i = 0; i < ips.length; i++) {
    var ip = normalizeTailnetIPv4(ips[i]);
    if (ip !== "" && !seen[ip]) {
      seen[ip] = true;
      result.push(ip);
    }
  }
  return result;
}

function filterIPv6(ips) {
  var result = [];
  var seen = {};
  if (!ips || typeof ips.length !== "number") return result;

  for (var i = 0; i < ips.length; i++) {
    var ip = normalizeTailnetIPv6(ips[i]);
    if (ip !== "" && !seen[ip]) {
      seen[ip] = true;
      result.push(ip);
    }
  }
  return result;
}

function normalizeOs(os) {
  var value = sanitizeDisplay(os, 32).toLowerCase();
  if (value === "linux" || value === "macos" || value === "ios" || value === "windows" || value === "android" || value === "mullvad") {
    return value;
  }
  return value;
}

function osIcon(os) {
  var value = normalizeOs(os);
  if (value === "linux") return "󰌽";
  if (value === "macos" || value === "ios") return "󰀵";
  if (value === "windows") return "󰍲";
  if (value === "android") return "󰀲";
  if (value === "mullvad") return "󰖂";
  return "󰟀";
}

function accountLabel(account) {
  if (!account) return "Unknown account";

  var nickname = sanitizeDisplay(account.nickname, MAX_LONG_DISPLAY);
  if (nickname !== "") return nickname;

  var tailnet = cleanDnsName(account.tailnet);
  if (tailnet !== "") return tailnet;

  var login = sanitizeDisplay(account.account, MAX_LONG_DISPLAY);
  if (login !== "") return login;

  var id = normalizeOpaqueId(account.id);
  if (id !== "") return id;
  return "Unknown account";
}

function isGenericHostName(text) {
  if (text === "localhost") return true;
  return cleanDnsName(text) !== "";
}

function isGenericIPv4(text) {
  if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(text)) return false;
  var parts = text.split(".");
  for (var i = 0; i < 4; i++) {
    var number = Number(parts[i]);
    if (!isFinite(number) || number < 0 || number > 255 || Math.floor(number) !== number) return false;
  }
  return true;
}

function isGenericIPv6(text) {
  return !!expandIPv6(text.toLowerCase());
}

function validateAuthUrl(value) {
  if (typeof value !== "string") return "";

  var text = value.trim();
  if (text === "" || text.length > MAX_AUTH_URL) return "";
  if (/[\u0000-\u001F\u007F-\u009F\s]/.test(text)) return "";
  var match = /^(https):\/\/([^/?#]+)([/?#].*)?$/i.exec(text);
  if (!match) return "";

  var authority = match[2].toLowerCase();
  if (authority !== "login.tailscale.com") return "";
  if (!/^\/a\/[A-Za-z0-9_-]{1,512}$/.test(match[3] || "")) return "";

  return text;
}

function loginPlan(needsLogin, authUrl) {
  var url = validateAuthUrl(authUrl);
  if (needsLogin === true && url !== "") {
    return { authUrl: url, command: [] };
  }
  return { authUrl: "", command: ["tailscale", "up"] };
}

function hasFileSharing(self) {
  var capMap = self && self.CapMap;
  if (capMap && typeof capMap === "object" && hasOwnProperty.call(capMap, FILE_SHARING_CAPABILITY)) return true;

  var capabilities = self && self.Capabilities;
  if (!capabilities || typeof capabilities.length !== "number") return false;
  for (var i = 0; i < capabilities.length; i++) {
    if (asString(capabilities[i]) === FILE_SHARING_CAPABILITY) return true;
  }
  return false;
}

function isTaildropTarget(peer, selfUserId) {
  var target = peer && peer.TaildropTarget;
  if (typeof target === "number" && target !== 0) return target === 1;

  var owner = normalizeOpaqueId(peer && peer.UserID);
  var selfId = normalizeOpaqueId(selfUserId);
  return owner !== "" && selfId !== "" && owner === selfId;
}

function isMullvadHost(name) {
  var value = cleanDnsName(name);
  var suffix = ".mullvad.ts.net";
  return value.length > suffix.length && value.indexOf(suffix) === value.length - suffix.length;
}

function isMullvadPeer(peer) {
  return isMullvadHost(peer && peer.DNSName) || isMullvadHost(peer && peer.HostName);
}

function sanitizeTags(tags) {
  var result = [];
  if (!tags || typeof tags.length !== "number") return result;

  for (var i = 0; i < tags.length && result.length < MAX_TAGS; i++) {
    var tag = sanitizeDisplay(tags[i], MAX_DISPLAY);
    if (tag !== "") result.push(tag);
  }
  return result;
}

function firstValidOpaqueId(peer, fallback) {
  var keys = [
    fallback,
    peer && peer.ID,
    peer && peer.Id,
    peer && peer.StableID,
    peer && peer.StableId,
    peer && peer.PublicKey,
    peer && peer.NodeKey,
    peer && peer.Key
  ];

  for (var i = 0; i < keys.length; i++) {
    var id = normalizeOpaqueId(keys[i]);
    if (id !== "") return id;
  }
  return "";
}

function peerFromStatus(id, peer) {
  var safeId = firstValidOpaqueId(peer || {}, id);
  if (safeId === "") return null;

  var dnsName = cleanDnsName(peer && peer.DNSName);
  var displayName = displayHostName(peer && peer.HostName, dnsName);
  var os = normalizeOs(peer && peer.OS);
  return {
    id: safeId,
    HostName: displayName,
    UserID: normalizeOpaqueId(peer && peer.UserID),
    TaildropTarget: typeof (peer && peer.TaildropTarget) === "number" ? peer.TaildropTarget : 0,
    DNSName: dnsName,
    DisplayName: displayName,
    TailscaleIPs: filterIPv4((peer && peer.TailscaleIPs) || []),
    TailscaleIPv6: filterIPv6((peer && peer.TailscaleIPs) || []),
    Online: peer && peer.Online === true,
    OS: os,
    OSIcon: osIcon(os),
    Tags: sanitizeTags((peer && peer.Tags) || []),
    ExitNodeOption: peer && peer.ExitNodeOption === true,
    ExitNode: peer && peer.ExitNode === true,
    Mullvad: isMullvadPeer(peer || {})
  };
}

function compareText(a, b) {
  a = asString(a).toLowerCase();
  b = asString(b).toLowerCase();
  if (a < b) return -1;
  if (a > b) return 1;
  return 0;
}

function parseJsonDocument(raw) {
  var text = boundedText(raw);
  if (text === null) return { ok: false, code: "too_large" };
  text = text.trim();
  if (text === "") return { ok: true, empty: true, value: null };

  try {
    return { ok: true, empty: false, value: JSON.parse(text) };
  } catch (_error) {
    return { ok: false, code: "invalid_json" };
  }
}

function eachPeer(rawPeers, visitor) {
  if (!rawPeers) return;

  if (Array.isArray(rawPeers)) {
    for (var i = 0; i < rawPeers.length; i++) visitor("", rawPeers[i]);
    return;
  }

  if (typeof rawPeers === "object") {
    for (var key in rawPeers) {
      if (hasOwnProperty.call(rawPeers, key)) visitor(key, rawPeers[key]);
    }
  }
}

function parseStatus(raw) {
  var document = parseJsonDocument(raw);
  if (!document.ok) {
    return { ok: false, unavailable: true, message: "Status error", error: "invalid_status" };
  }
  if (document.empty) return { ok: true, unavailable: true, message: "Disconnected" };

  var data = document.value;
  if (!data || typeof data !== "object" || Array.isArray(data)) {
    return { ok: false, unavailable: true, message: "Status error", error: "invalid_status" };
  }

  var backendState = sanitizeDisplay(data.BackendState, 32) || "Unknown";
  var self = data.Self && typeof data.Self === "object" ? data.Self : {};
  var selfIps = filterIPv4(self.TailscaleIPs || data.TailscaleIPs || []);
  var peers = [];
  var exitNodes = [];

  eachPeer(data.Peer || data.Peers, function(id, peer) {
    if (peers.length >= MAX_PEERS) return;

    var normalized = peerFromStatus(id, peer || {});
    if (!normalized) return;
    if (normalized.Mullvad) return;
    if (!normalized.Online) return;

    peers.push(normalized);
    if (normalized.ExitNodeOption === true && exitNodes.length < MAX_PEERS) exitNodes.push(normalized);
  });

  peers.sort(function(a, b) {
    return compareText(a.DisplayName, b.DisplayName) || compareText(a.id, b.id);
  });
  exitNodes.sort(function(a, b) {
    return compareText(a.DisplayName, b.DisplayName) || compareText(a.id, b.id);
  });

  var authUrl = validateAuthUrl(data.AuthURL);
  return {
    ok: true,
    unavailable: false,
    backendState: backendState,
    running: backendState === "Running",
    needsLogin: backendState === "NeedsLogin",
    authUrl: authUrl,
    selfName: displayHostName(self.HostName, self.DNSName),
    selfDnsName: cleanDnsName(self.DNSName),
    selfIp: selfIps.length > 0 ? selfIps[0] : "",
    selfUserId: normalizeOpaqueId(self.UserID),
    fileSharing: hasFileSharing(self),
    peers: peers,
    onlinePeers: peers,
    exitNodes: exitNodes,
    tailnetExitNodes: exitNodes
  };
}

function normalizeAccountValue(value) {
  var dns = cleanDnsName(value);
  if (dns !== "") return dns;
  return sanitizeDisplay(value, MAX_LONG_DISPLAY);
}

function parseSelectedAccountId(parsed) {
  if (!parsed || typeof parsed !== "object") return "";

  var keys = [
    parsed.CurrentProfileID,
    parsed.CurrentProfileId,
    parsed.currentProfileId,
    parsed.currentProfileID,
    parsed.SelectedProfileID,
    parsed.SelectedProfileId,
    parsed.selectedProfileId,
    parsed.current,
    parsed.Current,
    parsed.Selected,
    parsed.selected
  ];

  for (var i = 0; i < keys.length; i++) {
    var direct = normalizeOpaqueId(keys[i]);
    if (direct !== "") return direct;
  }

  var objects = [parsed.CurrentProfile, parsed.currentProfile, parsed.SelectedProfile, parsed.selectedProfile];
  for (i = 0; i < objects.length; i++) {
    var object = objects[i];
    if (object && typeof object === "object") {
      var nested = normalizeOpaqueId(object.ID || object.Id || object.id || object.Profile || object.profile);
      if (nested !== "") return nested;
    }
  }
  return "";
}

function normalizeAccount(rawAccount, fallbackId, selectedId) {
  if (!rawAccount || typeof rawAccount !== "object") return null;

  var id = normalizeOpaqueId(
    rawAccount.id || rawAccount.ID || rawAccount.Id || rawAccount.Profile || rawAccount.profile || fallbackId
  );
  if (id === "") return null;

  var account = {
    id: id,
    nickname: sanitizeDisplay(rawAccount.nickname || rawAccount.Nickname || rawAccount.name || rawAccount.Name || "", MAX_LONG_DISPLAY),
    tailnet: normalizeAccountValue(rawAccount.tailnet || rawAccount.Tailnet || ""),
    account: sanitizeDisplay(rawAccount.account || rawAccount.Account || rawAccount.loginName || rawAccount.LoginName || rawAccount.user || rawAccount.User || rawAccount.email || rawAccount.Email || "", MAX_LONG_DISPLAY),
    selected: rawAccount.selected === true || rawAccount.Selected === true || rawAccount.current === true || rawAccount.Current === true
  };

  if (selectedId !== "" && account.id === selectedId) account.selected = true;
  return account;
}

function appendAccountCollection(target, collection, selectedId) {
  if (!collection) return;

  if (Array.isArray(collection)) {
    for (var i = 0; i < collection.length && target.length < MAX_ACCOUNTS; i++) {
      var account = normalizeAccount(collection[i], "", selectedId);
      if (account) target.push(account);
    }
    return;
  }

  if (typeof collection === "object") {
    for (var key in collection) {
      if (!hasOwnProperty.call(collection, key) || target.length >= MAX_ACCOUNTS) continue;
      var mapped = normalizeAccount(collection[key], key, selectedId);
      if (mapped) target.push(mapped);
    }
  }
}

function parseAccounts(raw) {
  var document = parseJsonDocument(raw);
  if (!document.ok || document.empty) {
    return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" };
  }

  var parsed = document.value;
  var selectedId = parseSelectedAccountId(parsed);
  var accounts = [];

  if (Array.isArray(parsed)) {
    appendAccountCollection(accounts, parsed, selectedId);
  } else if (parsed && typeof parsed === "object") {
    appendAccountCollection(accounts, parsed.Profiles, selectedId);
    appendAccountCollection(accounts, parsed.profiles, selectedId);
    appendAccountCollection(accounts, parsed.Accounts, selectedId);
    appendAccountCollection(accounts, parsed.accounts, selectedId);
    if (accounts.length === 0) appendAccountCollection(accounts, parsed, selectedId);
  }

  var selected = null;
  for (var i = 0; i < accounts.length; i++) {
    if (accounts[i].selected === true) {
      selected = accounts[i];
      break;
    }
  }

  return {
    accounts: accounts,
    selectedAccountId: selected ? selected.id : "",
    selectedAccountLabel: selected ? accountLabel(selected) : ""
  };
}

function sliceTableColumn(line, start, end) {
  var text = asString(line);
  if (start < 0 || start >= text.length) return "";
  if (end < 0) return text.substring(start).trim();
  return text.substring(start, Math.min(end, text.length)).trim();
}

function normalizeTableField(value, maxLen) {
  var text = sanitizeDisplay(value, maxLen);
  if (text === "-") return "";
  return text;
}

function parseExitNodeList(raw) {
  var text = boundedText(raw);
  if (text === null || text.trim() === "") return [];

  var lines = text.split(/\r?\n/);
  var header = "";
  var headerIndex = -1;
  for (var i = 0; i < lines.length; i++) {
    if (/^\s*IP\s+HOSTNAME\s+COUNTRY\s+CITY\s+STATUS\s*$/i.test(lines[i])) {
      header = lines[i];
      headerIndex = i;
      break;
    }
  }
  if (headerIndex === -1) return [];

  var ipStart = header.indexOf("IP");
  var hostStart = header.indexOf("HOSTNAME");
  var countryStart = header.indexOf("COUNTRY");
  var cityStart = header.indexOf("CITY");
  var statusStart = header.indexOf("STATUS");
  var result = [];
  var byHost = {};

  for (var j = headerIndex + 1; j < lines.length && result.length < MAX_EXIT_ROWS; j++) {
    var line = lines[j];
    if (/^\s*$/.test(line) || /^\s*#/.test(line)) continue;

    var ipText = sliceTableColumn(line, ipStart, hostStart);
    var host = cleanDnsName(sliceTableColumn(line, hostStart, countryStart));
    var country = normalizeTableField(sliceTableColumn(line, countryStart, cityStart), MAX_DISPLAY);
    var city = normalizeTableField(sliceTableColumn(line, cityStart, statusStart), MAX_DISPLAY);
    var status = normalizeTableField(sliceTableColumn(line, statusStart, -1), MAX_LONG_DISPLAY);
    if (host === "") continue;

    var ipv4 = normalizeTailnetIPv4(ipText);
    var ipv6 = ipv4 === "" ? normalizeTailnetIPv6(ipText) : "";
    if (ipv4 === "" && ipv6 === "") continue;

    var mullvad = isMullvadHost(host);
    var display = shortDnsName(host) || host;
    if (mullvad && country !== "") {
      display = city !== "" && city.toLowerCase() !== "any" ? city + ", " + country : country;
      display = sanitizeDisplay(display, MAX_LONG_DISPLAY);
    }

    var node = {
      id: mullvad ? normalizeOpaqueId("mullvad:" + host) : normalizeOpaqueId("exit:" + host),
      HostName: host,
      DNSName: host,
      DisplayName: display,
      TailscaleIPs: ipv4 !== "" ? [ipv4] : [],
      TailscaleIPv6: ipv6 !== "" ? [ipv6] : [],
      Online: !/\boffline\b/i.test(status),
      OS: mullvad ? "mullvad" : "",
      OSIcon: osIcon(mullvad ? "mullvad" : ""),
      Tags: [],
      ExitNodeOption: true,
      ExitNode: /\b(selected|current|active)\b/i.test(status),
      Mullvad: mullvad,
      Country: country,
      City: city,
      Status: status
    };

    if (byHost[host]) {
      for (var propertyName in node) {
        if (hasOwnProperty.call(node, propertyName)) byHost[host][propertyName] = node[propertyName];
      }
    } else {
      byHost[host] = node;
      result.push(node);
    }
  }

  result.sort(function(a, b) {
    if (a.Mullvad !== b.Mullvad) return a.Mullvad ? 1 : -1;
    return compareText(a.DisplayName, b.DisplayName) || compareText(a.HostName, b.HostName);
  });
  return result;
}

function cloneObject(source) {
  var result = {};
  for (var name in source) {
    if (hasOwnProperty.call(source, name)) result[name] = source[name];
  }
  return result;
}

function mullvadRegionOptions(nodes) {
  var values = Array.isArray(nodes) ? nodes : [];
  var seen = {};
  var result = [];

  for (var i = 0; i < values.length && result.length < MAX_REGIONS; i++) {
    var node = values[i] || {};
    if (node.Mullvad !== true) continue;

    var country = sanitizeDisplay(node.Country, MAX_DISPLAY);
    var city = sanitizeDisplay(node.City, MAX_DISPLAY);
    if (country === "" || city === "" || city.toLowerCase() === "any") continue;

    var key = country.toLowerCase() + "\n" + city.toLowerCase();
    if (seen[key]) continue;
    seen[key] = true;

    var option = cloneObject(node);
    option.id = opaqueIdFromParts("mullvad-region", country, city);
    option.DisplayName = sanitizeDisplay(city + ", " + country, MAX_LONG_DISPLAY);
    option.Country = country;
    option.City = city;
    option.Mullvad = true;
    option.MullvadRegion = true;
    option.OS = "mullvad";
    option.OSIcon = osIcon("mullvad");
    option.ExitNodeOption = true;
    result.push(option);
  }

  result.sort(function(a, b) {
    return compareText(a.Country, b.Country) || compareText(a.City, b.City);
  });
  return result;
}

function mullvadCountryOptions(nodes) {
  return mullvadRegionOptions(nodes);
}

function mullvadCityRegionOptions(nodes) {
  return mullvadRegionOptions(nodes);
}

var api = {
  MAX_INPUT: MAX_INPUT,
  MAX_PEERS: MAX_PEERS,
  MAX_ACCOUNTS: MAX_ACCOUNTS,
  MAX_EXIT_ROWS: MAX_EXIT_ROWS,
  MAX_REGIONS: MAX_REGIONS,
  sanitizeDisplay: sanitizeDisplay,
  normalizeOpaqueId: normalizeOpaqueId,
  normalizeTailnetIPv4: normalizeTailnetIPv4,
  normalizeTailnetIPv6: normalizeTailnetIPv6,
  filterIPv4: filterIPv4,
  filterIPv6: filterIPv6,
  cleanDnsName: cleanDnsName,
  shortDnsName: shortDnsName,
  displayHostName: displayHostName,
  osIcon: osIcon,
  accountLabel: accountLabel,
  validateAuthUrl: validateAuthUrl,
  loginPlan: loginPlan,
  hasFileSharing: hasFileSharing,
  isTaildropTarget: isTaildropTarget,
  isMullvadHost: isMullvadHost,
  isMullvadPeer: isMullvadPeer,
  peerFromStatus: peerFromStatus,
  parseExitNodeList: parseExitNodeList,
  mullvadRegionOptions: mullvadRegionOptions,
  mullvadCountryOptions: mullvadCountryOptions,
  mullvadCityRegionOptions: mullvadCityRegionOptions,
  parseStatus: parseStatus,
  parseAccounts: parseAccounts
};

if (typeof module !== "undefined" && module.exports) module.exports = api;
