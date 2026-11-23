# « Show tiles » on the maps, issue #246: design note

**Status: design**, written on 2026-11-23, before any code of [#246](https://github.com/Skyman21m/bull-market/issues/246), without any request to a tile server, a coordinator or a relay, and without running Tor or the app.
Where the code later differs, the code and its pull requests are right, and this note is updated.
The owner asked for the reference's « Show tiles » on both maps, off by default, the pinned point still randomized as today (issue #246, 2026-11-20); everything else here is a proposal of this note, said as « this note recommends », and the open questions are in § 9.

Reference: RoboSats/robosats at commit ff1998c (`sources/robosats`), frontend paths relative to `frontend/src/`.
Bull Market: `main` at `9a0d69ec6`.

**The decisive fact, in one line:** the embedded Tor refuses every destination that is not an onion service (`packages/bull_tor/lib/src/data/onion_tor_backend.dart:17-31`, `SocksPolicy.onionOnly`, applied to the client at `:129-135` and to every session at `:309-313`), so the tiles of `tile.openstreetmap.org` cannot go through Tor without a change to `packages/bull_tor` (§ 3).

## 1. The reference

**Where.** Three maps carry the switch: the book's map (`components/Charts/MapChart/index.tsx`), the map where a maker chooses the meeting point (`components/Dialogs/F2fMap.tsx`, interactive, opened by `MakerForm.tsx:651`), and the same dialog read-only in an order's details (`components/OrderDetails/index.tsx:286-298`, opened at `:415`).
Bull Market has the first two; its order details show the place as numbers (`features/p2p/lib/src/ui/trade/trade_order_details.dart:15`, `:163`), so the third map is outside #246 (§ 10).

**The switch.** A small `Switch` with a picture icon, tooltip « Show tiles », at the right of the map's title (`F2fMap.tsx:105-125`, `MapChart/index.tsx:109-130`); off at first (`useState<boolean>(false)`, `F2fMap.tsx:40`, `MapChart/index.tsx:37`).
The first time it is turned on, a dialog opens instead (`F2fMap.tsx:116-121`); « Acknowledged » turns the tiles on, « Close » leaves them off; once acknowledged, the switch toggles freely.

**The dialog**, word for word (`F2fMap.tsx:75-98`, the same at `MapChart/index.tsx:61-84`):
- title « Download high resolution map? »;
- body « By doing so, you will be fetching map tiles from a third-party provider. Depending on your setup, private information might be leaked to servers outside the RoboSats federation. »;
- buttons « Close » and « Acknowledged ».

**Nothing is remembered.** The switch and the acknowledgment are component state (`useState`, `F2fMap.tsx:40-42`, `MapChart/index.tsx:37-39`): every new map starts without tiles and asks again.

**The tiles.** Leaflet `^1.9.4` with react-leaflet `^5.0.0` (`frontend/package.json:89`, `:99`); a `TileLayer` with `url='https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png'` and `referrerPolicy='no-referrer'` (`components/Map/index.tsx:179-185`), in place of the bundled GeoJSON world (`:169-178`); `maxZoom={15}` (`:162`), zoom 1 at first (`:164`), 6 on a saved point (`MakerForm.tsx:664`, `OrderDetails/index.tsx:291`).
An attribution is declared (`:181`) but the control that shows it is off (`attributionControl={false}`, `:165`): the reference shows no attribution.
No cache of its own: whatever the browser or the WebView keeps.

**Where the tile requests go, client by client** (the most important fact of this section):
- **Desktop app**: through Tor. `desktopApp/index.ts:110-113` sets `socks://localhost:9050`, the Tor it starts, as the proxy of the whole Electron session, so the tiles leave by a Tor exit relay.
- **Android app**: **outside Tor, as far as the code shows.** The frontend runs in a WebView loaded from `file:///android_asset/index.html` (`android/app/src/main/java/com/robosats/MainActivity.kt:445`); Tor is the proxy of the OkHttp client behind the JavaScript bridge only (`HttpClientManager.setDefaultProxy`, `:289`); the WebView has no proxy (no `ProxyController` anywhere in `android/`), and the client installed once Tor is up overrides `shouldOverrideUrlLoading` only, with no `shouldInterceptRequest` (`:361-387`), so Leaflet's `<img>` tiles are loaded by the WebView's own network stack, from the phone's IP address, with the User-Agent `AndroidRobosats` (`:435`) and the cache off (`LOAD_NO_CACHE`, `:492`).
  The app's own agent notes say the opposite (`android/app/src/main/java/com/robosats/AGENTS.md:27-29`: « shouldInterceptRequest: allows file:///android_asset/ only; all other requests blocked »); the code wins, and if the notes were right the tiles would not show at all. Not observed on a device. With the Orbot option (`settings_use_proxy=false`), it depends on the user's Orbot setup.
- **Web, over the onion**: the browser fetches the tiles itself. In Tor Browser they leave by a Tor exit, outside the federation; in an ordinary browser on the self-hosted client (`nodeapp/README.md`: only the API goes through the node's Tor) they leave in clear. This is the « Depending on your setup » of the dialog.
  The OSM wiki says Tor Browser sends no `Referer` from an onion site and that tiles without one may be refused (§ 4), and the reference sets `no-referrer` anyway: whether its web tiles load at all is not established.

## 2. Today in Bull Market

**What draws the maps.** Both maps are drawn by the app, with no map dependency and no request (`AGENTS.md`, « The Map view of the book (#30) »): `MapChartView` (`features/p2p/lib/src/ui/map_chart_view.dart:30`) for the book, `LocationMapDialog` (`ui/location_map_dialog.dart:21`) for the meeting point, both painting with `MapChartPainter.paintWorld` and `paintPin` (`map_chart_view.dart:911`, `:943`; the dialog's `_LocationPainter`, `location_map_dialog.dart:318`).
The world is Natural Earth's 1:110m countries, about 42 KB, bundled (`features/p2p/assets/map/world_110m.bin`, read by `WorldMap.parse`, `domain/world_map.dart`), in Web Mercator as Leaflet projects it, zooms 0 to 15 (`domain/web_mercator.dart`: `tileSize` 256, `maxZoom` 15).
So the projection, the camera (`MapCamera`, `map_chart_view.dart:541`) and the tile size are already Leaflet's: a tile `z/x/y` maps onto the painter's world square with no new mathematics.

**The pinned point.** `MeetingPoint.randomized` (`domain/meeting_point.dart:17-29`) moves the place tapped by up to 0.05° on each axis (about 5.5 km of latitude), from `Random.secure` (`p2p_locator.dart:152`), then rounds it; the place tapped never leaves the dialog. Nothing reads the device's position; no permission is asked. #246 changes none of this.

**How the feature reaches the network today.** `TorCoordinatorTransport` (`data/tor_coordinator_transport.dart`) sends every coordinator request and every relay publication through the embedded Tor:
- each session comes from `tor().embedded.sessions.open()` (`:180`), a « circuit-isolated SOCKS route » of its own (`packages/bull_tor/lib/src/domain/entities/tor_session.dart`), with its own `HttpClient` built by `TorHttpClientFactory` (`packages/bull_tor/lib/src/data/tor_http_client_factory.dart:23-64`), whose only connection factory is SOCKS5, the host name sent to Tor unresolved, TLS done over the SOCKS socket for `https` (`:46-49`);
- one session per coordinator origin for the anonymous reads, one more per coordinator and robot for a robot's requests, so nothing ties a robot to another robot or to the anonymous reads (doc comment, `:88-91`);
- only `http` to a `.onion` host (`:110`, `_isOnion` `:209`), no `User-Agent` (decision of 2026-11-10, `:128-130`), `Accept-Encoding: identity`.
Below it, `bull_tor` adds its own fence: the Arti client and each session are started with `SocksPolicy.onionOnly` (`onion_tor_backend.dart:31`), « refusing non-onion destinations » because the loopback SOCKS port has no authentication and any app on the device could use it (`:17-30`).
The `SocksPolicy` type itself lives in `bull_sdk`, whose source is not on disk: its exact behaviour is taken from that comment.

## 3. Fetching the tiles through Tor

**Not possible without changing `packages/bull_tor`.** Every Tor session the feature can open is onion-only, and no onion service of OpenStreetMap's tiles was found (§ 4).
A tile request sent through today's path fails at the SOCKS step, so nothing leaks, and nothing shows.

**The options**, none of which this note may carry out:
- **A. A narrow change to `bull_tor`**: a second kind of session, opened only on request, whose policy lets it reach the clearnet; everything else stays onion-only. Whether a session may have a wider policy than the client it belongs to is not established (`bull_sdk` not read). Cost: a change to Bull's own package, to carry across every update from Bull's releases, which this fork follows, and, while such a session is open, a loopback port through which any app of the device could reach the clearnet by Tor, which is exactly the exposure `onion_tor_backend.dart:17-30` narrows; so it would be opened only while tiles are shown and closed at once after.
- **B. A second Tor client started by the feature itself** through `bull_sdk`, with a clearnet policy: no change to `bull_tor`, but a second bootstrap (about a minute on 2026-11-10, `tor_coordinator_transport.dart:27`), twice the memory and battery, the same loopback exposure, and a feature reaching past `tor.dart`, which the package forbids (`packages/bull_tor/lib/tor.dart`, header). This note does not recommend it.
- **C. Outside Tor**, as the reference's Android app does by its code: the owner's rule forbids it unless he decides it knowingly.
- **D. No tiles yet**: the switch is not offered, as today.

**If A is chosen, the rules of this note:**
- **Isolation**: one tile session per map opened with tiles, never used for anything else, closed when the map closes or the switch goes off; never a robot's session nor an anonymous coordinator session; so the tile server cannot tie two openings, two robots, or a robot to its coordinator requests by a shared circuit.
- **Never outside Tor**: the tile client is built only from a `TorSession`'s endpoint (`TorHttpClientFactory.create` takes no null, `tor_http_client_factory.dart:13-18`); the tile source accepts only `https://tile.openstreetmap.org/{z}/{x}/{y}.png` with whole `z` from 0 to 15 and `x`, `y` within the zoom; no redirect followed; a response bounded in size (a tile is a few tens of KB) and decoded only as PNG.
- **Tor not ready**: the switch can be turned on; the countries stay drawn and tiles appear as they arrive; the session waits for Tor as the coordinator requests do (`P2pTorState`, `coordinatorRequestDeadline`); when it cannot open or a tile fails, the countries stay, with one short line « Map tiles unavailable » (the app's text, the reference having none), and the next pan or zoom tries again on a new session; never a fallback outside Tor.
- **Speed**: not measured. Each tile is one HTTPS request through a Tor exit; a phone screen at one zoom needs about 6 to 20 tiles.

## 4. The tile provider

Pages read on 2026-11-23:
- the tile usage policy, <https://operations.osmfoundation.org/policies/tiles/> (no date shown);
- « Blocked tiles », <https://wiki.openstreetmap.org/wiki/Blocked_tiles> (last edited 2026-11-12);
- « Technical updates to the tile.openstreetmap.org service », community.openstreetmap.org, topic 133421 (2025-07-30);
- the OSMF privacy policy, <https://osmfoundation.org/wiki/Privacy_Policy> (last edited 2026-01-25).

What the policy asks of an app:
- the exact URL `https://tile.openstreetmap.org/{z}/{x}/{y}.png`; the `a.`, `b.`, `c.` hosts the reference uses « may be slower or withdrawn without notice »;
- « a distinct, stable User-Agent naming your app »; a library's default (flutter_map's `flutter_map (unknown)`) « will be blocked », and never another app's or a browser's;
- a `Referer` from websites; « Native apps usually do not have a referer, this is ok »;
- honour `Cache-Control`, `Expires` and `ETag`, « If your cache cannot read them, cache each tile for at least 7 days », never send `no-cache`;
- no bulk download, no prefetch of tiles not in view, no offline use;
- the attribution « clearly on the map », not hidden;
- under « You must not »: « tunnel all clients behind a single, anonymous identity » (said of proxies); caching proxies « generally » not recommended;
- best effort, « no SLA », and blocks without notice when use degrades the service; since 2025-07-30, a refused tile comes back as an error picture with HTTP 200 and an `x-blocked` header.

What it says of Tor: nothing; Tor, VPNs and exit relays are not mentioned.
What is known publicly: the wiki says Tor Browser sends no `Referer` from onion sites and suggests `X-Requested-With` or another provider; the Tor blocks found (captchas, a Cloudflare challenge) concern the website and the editing API, not the tiles, which a community thread says Fastly serves.
**Not established** (no request was made): whether `tile.openstreetmap.org` serves requests from Tor exits today, at what speed, whether its automatic `Referer` block applies to a native app with its own User-Agent, and how long tile logs are kept (the privacy policy does not say).
No official onion service of the tiles was found.

## 5. What the provider learns

For each tile request through Tor (option A):
- **the provider** (OSMF and its CDN): the exit relay's address, not the phone's; the tile's zoom, `x` and `y`, so the area looked at, down to one tile of zoom 15 (about 1.2 km wide at the equator, less towards the poles); the time; the headers sent: the User-Agent the policy requires (§ 9, question 2), no `Referer`, no cookie;
- **the exit relay**: the host name `tile.openstreetmap.org` and the volume and timing of the traffic, not the tiles (HTTPS);
- **a network observer near the phone**: Tor traffic only, no DNS query.

**What it reveals of a meeting point.** The coordinator publishes the point moved by up to 0.05° (§ 2), but the tiles the maker loads to aim show the true neighbourhood, at up to zoom 15, a few minutes before an order whose point lies within 5.5 km of it appears in the public book. Whoever holds the provider's logs and reads the book can match the two by time and place and so undo much of the randomization; through Tor, without learning who the maker is.
On the book's map, the areas looked at say where the user looks for a trade.

**What reduces it**: Tor (no IP address); no `Referer` and a User-Agent shared by every user of the app; a new session per opening; the zoom capped at 15, as the reference; only the tiles in view, no neighbouring tiles fetched ahead; the cache in memory (§ 7), so a tile seen again is not asked again.

**Compared with the reference**: its Android app, by its code, gives the provider the phone's IP address and `AndroidRobosats` with every area looked at; its desktop app gives an exit address and Chromium's User-Agent, as option A would; Tor Browser, an exit address.

## 6. The library

**flutter_map**, Leaflet's Dart counterpart (fleaflet.dev, BSD-3-Clause, 8.3.2 on pub.dev): not in Bull nor in the workspace's lock; it brings `latlong2`, `proj4dart`, `path_provider`, `uuid` and more; a disk cache on by default since 8.2 (up to 1 GB in the system's cache folder; `DisabledMapCachingProvider` turns it off); `NetworkTileProvider(httpClient: …)` takes a `package:http` client, so an `IOClient` over the Tor `HttpClient` would carry its requests; its weight was not measured.
Adopting it means rebuilding both maps on it: the camera, gestures, pins, groups (a plugin), screen-reader nodes and tests of #30 and #189, all already matching the reference.

**Tiles drawn by the existing painter**: a tile layer under the countries in `paintWorld`'s transform: the tiles of the view at the whole zoom below the camera's (0 to 15), fetched by a `MapTileSource` port of the feature, decoded with `instantiateImageCodec`, drawn scaled, a repaint as each arrives, the requests for tiles that left the view dropped.
No new dependency, the HTTP client fully the feature's own (session, headers, size bound, no disk), the gestures and pins untouched; the cost is a small tile cache and its tests.

**This note recommends the existing painter**: a library is admitted where the reference has one, but here it would replace reviewed work, bring a disk cache to switch off and a client to wrap, and change nothing the user sees.

## 7. Cache and storage

- **Memory only**: decoded tiles kept in a bounded cache (for instance 256 tiles, a few MB) for the life of the app's process, nothing written to disk; the tile session and its circuits are closed with the map.
- A disk cache would leave on the phone the list and pictures of every area looked at, the meeting place included, readable by whoever holds the unlocked phone or a backup; this note recommends against it.
- The policy expects tiles kept 7 days or per their headers; a memory cache honours the headers while the app runs and forgets at the next start. The volume is a few dozen tiles a session, far from bulk use. This shortfall is said in the pull request.
- `FEATURES.md` and `AGENTS.md` say, when the code comes: the request path, the session rule, the memory-only cache, the User-Agent, the attribution, and that #30's « no tile, no request » no longer holds once the switch is on.

## 8. The dialog and its texts

Taken word for word from the reference, in every language the feature has, from the reference's locale files as the feature does:
- English (`frontend/static/locales/en.json:202-206`): « Show tiles », « Download high resolution map? », the body of § 1, « Close », « Acknowledged »;
- French (`fr.json:202-206`): « Afficher les tuiles », « Télécharger une carte haute résolution? », « Fermer », « Confirmer »; the body is left in English in the reference's French file (`:203`).

What differs if the tiles go through Tor (option A): the reference's body stays true (« Depending on your setup » covers it). It does not say what the provider learns. This note recommends keeping the reference's text whole and adding one line of the app's own under it: « Through Tor: OpenStreetMap sees the area you look at, not your address. » (the owner's rule of 2026-11-20: explanations short, more behind « See details »).

Deviations from the reference, each with its reason:
- the attribution « © OpenStreetMap contributors » shown on the map while tiles are on, where the reference hides it: the provider's policy;
- `tile.openstreetmap.org` without `a.`, `b.`, `c.`: the provider's policy;
- a User-Agent naming the app, where the feature sends none to coordinators: the provider's policy (§ 9);
- the tiles through Tor, where the reference's Android app sends them in clear: the owner's rule;
- the line under the dialog's text, and « Map tiles unavailable »: the app's;
- kept as the reference: off by default, the dialog the first time on each map opened, nothing remembered, zoom up to 15, the switch's place at the right of the title.

## 9. Decisions for the owner

1. **How do the tiles travel?** This note recommends A, a narrow change to `bull_tor` (a session that may leave Tor's onion services, opened only while tiles show). The cost: a change to Bull's package to carry at each update, and an open door for other apps of the phone while tiles show. C (outside Tor, as RoboSats' Android app) costs the user's IP address to the provider; D costs the feature.
2. **What name does the app give the tile server?** OSM blocks requests without an app name. This note recommends a fixed `BullMarket`, without version, the same for every user. The cost: the provider knows the requests come from this app; with few users, that alone narrows who looks.
3. **Where are tiles kept?** This note recommends memory only. The cost: below the provider's 7-day expectation, tiles asked again at each start; a disk cache would leave the areas looked at on the phone.
4. **The dialog**: this note recommends the reference's text whole plus one line of the app's (§ 8). The cost of the reference's text alone: the user is not told that the area looked at is seen.

## 10. Work plan

- **PR 1, only if question 1 is A**, in `packages/bull_tor`: the clearnet session, opened on request, closed by its owner, with its tests and a security review of the loopback exposure.
- **PR 2**, in `features/p2p`: the `MapTileSource` port and its Tor adapter (one session per map, the URL template fixed, whole zooms 0 to 15, size bound, PNG only, `x-blocked` read as a failure), the memory cache, the tile layer in `MapChartPainter` and `_LocationPainter`, the switch, the dialog and its texts in every language, the attribution, `FEATURES.md` and `AGENTS.md`.
- **Tests**, with a fake tile source and never a real request: no tile asked while the switch is off or before « Acknowledged »; the dialog again on a new map; only tiles in view and within zoom 15; nothing on disk; the session closed with the map and never shared with a coordinator session; a failed or blocked tile leaves the countries and the line; the pinned point still moved exactly as today; an architecture test that the tile source builds its client only from a `TorSession`.
- **Review**: the usual independent review, with a privacy part (session isolation, headers, no disk, no fallback outside Tor, the dialog's honesty).
- **Limits for the trial guide**: tiles may be slow or refused through Tor; the provider sees the area looked at; nothing is kept between starts; the order details still show the place as numbers.
- **Outside #246**: the read-only map of an order's place (`OrderDetails/index.tsx:286-298`) deserves its own issue, the owner's rule being that nothing out of scope goes without one.
