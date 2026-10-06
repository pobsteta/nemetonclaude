/*
 * nemeton-view.js — moteur commun des vues nemeton publiées dans Claude.
 *
 * Publié une fois dans un artéfact modèle, puis recopié dans chaque vue de
 * projet (`files: {"nemeton-view.js": {artifact: <modèle>, path: ...}}`).
 * Chaque vue n'apporte que sa page et ses données GeoJSON.
 *
 * Dépend de Leaflet 1.9.4 (global `L`, chargé depuis cdnjs avant ce fichier).
 * Aucune tuile externe : le fond est vectoriel (commune, sections, contexte).
 */
(function (global) {
  "use strict";

  var NV = {};

  /* ------------------------------------------------------------ langue */

  NV.lang = (function () {
    try {
      var l = (document.documentElement.lang || navigator.language || "fr").slice(0, 2);
      return l === "en" ? "en" : "fr";
    } catch (e) { return "fr"; }
  })();

  var dictionnaires = { fr: {}, en: {} };

  /** Ajoute des traductions : NV.textes({fr: {...}, en: {...}}). */
  NV.textes = function (d) {
    ["fr", "en"].forEach(function (l) {
      Object.keys(d[l] || {}).forEach(function (k) { dictionnaires[l][k] = d[l][k]; });
    });
  };

  /** Traduit une clé ; `{x}` est remplacé par vars.x. */
  NV.t = function (cle, vars) {
    var s = dictionnaires[NV.lang][cle];
    if (s == null) s = dictionnaires.fr[cle];
    if (s == null) s = cle;
    return String(s).replace(/\{(\w+)\}/g, function (_, k) {
      return vars && vars[k] != null ? vars[k] : "";
    });
  };

  /** Applique les traductions aux éléments [data-t] (texte) et [data-t-attr]. */
  NV.traduire = function (racine) {
    (racine || document).querySelectorAll("[data-t]").forEach(function (el) {
      el.textContent = NV.t(el.getAttribute("data-t"));
    });
    (racine || document).querySelectorAll("[data-t-placeholder]").forEach(function (el) {
      el.setAttribute("placeholder", NV.t(el.getAttribute("data-t-placeholder")));
    });
    (racine || document).querySelectorAll("[data-t-title]").forEach(function (el) {
      el.setAttribute("title", NV.t(el.getAttribute("data-t-title")));
      el.setAttribute("aria-label", NV.t(el.getAttribute("data-t-title")));
    });
    document.documentElement.lang = NV.lang;
  };

  NV.changerLangue = function (l) {
    NV.lang = l === "en" ? "en" : "fr";
    NV.stockage.ecrire("nemeton-langue", NV.lang);
    NV.traduire();
  };

  /* ------------------------------------------------------------ formats */

  var formats = {};
  function fmt(dec) {
    var cle = NV.lang + dec;
    if (!formats[cle]) {
      formats[cle] = new Intl.NumberFormat(NV.lang === "en" ? "en-GB" : "fr-FR",
        { minimumFractionDigits: dec, maximumFractionDigits: dec });
    }
    return formats[cle];
  }

  NV.nombre = function (x, dec) {
    if (x == null || x === "" || !isFinite(x)) return "—";
    return fmt(dec == null ? 0 : dec).format(Number(x));
  };

  /** Surface en hectares depuis des m² (contenance cadastrale). */
  NV.hectares = function (m2, dec) {
    return NV.nombre(m2 == null ? null : m2 / 1e4, dec == null ? 2 : dec) + " ha";
  };

  NV.date = function (iso) {
    if (!iso) return "—";
    var d = new Date(String(iso).replace(" ", "T"));
    if (isNaN(d)) return String(iso);
    return d.toLocaleDateString(NV.lang === "en" ? "en-GB" : "fr-FR",
      { day: "numeric", month: "long", year: "numeric" });
  };

  NV.echapper = function (s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  };

  /* ------------------------------------------------------------ stockage */

  /* Commodité par lecteur uniquement : peut être vide ou refusé. */
  NV.stockage = {
    lire: function (cle, defaut) {
      try {
        var v = global.localStorage.getItem(cle);
        return v == null ? defaut : JSON.parse(v);
      } catch (e) { return defaut; }
    },
    ecrire: function (cle, valeur) {
      try { global.localStorage.setItem(cle, JSON.stringify(valeur)); } catch (e) { /* sans stockage */ }
    },
    effacer: function (cle) {
      try { global.localStorage.removeItem(cle); } catch (e) { /* sans stockage */ }
    }
  };

  /* ------------------------------------------------------------ données */

  /**
   * Charge un fichier publié à côté de la page (fetch relatif), ou, à défaut,
   * un bloc <script type="application/json" data-fichier="nom"> embarqué.
   * Rend null si le fichier est absent.
   */
  NV.charger = function (nom) {
    var bloc = document.querySelector('script[type="application/json"][data-fichier="' + nom + '"]');
    if (bloc) {
      try { return Promise.resolve(JSON.parse(bloc.textContent)); } catch (e) { return Promise.reject(e); }
    }
    return fetch(nom, { cache: "no-cache" }).then(function (r) {
      if (r.status === 404) return null;
      if (!r.ok) throw new Error(nom + " : HTTP " + r.status);
      return r.json();
    });
  };

  /* ------------------------------------------------------------ couleurs */

  NV.css = function (nom) {
    return getComputedStyle(document.documentElement).getPropertyValue(nom).trim();
  };

  function hexRgb(h) {
    h = h.replace("#", "");
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
  }
  function rgbHex(c) {
    return "#" + c.map(function (v) {
      var s = Math.round(Math.max(0, Math.min(255, v))).toString(16);
      return s.length === 1 ? "0" + s : s;
    }).join("");
  }
  function interpoler(stops, t) {
    t = Math.max(0, Math.min(1, t));
    var n = stops.length - 1, i = Math.min(n - 1, Math.floor(t * n)), f = t * n - i;
    var a = hexRgb(stops[i]), b = hexRgb(stops[i + 1]);
    return rgbHex([a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f]);
  }

  /* Palettes perceptuelles : viridis (scores 0–100), divergente (écarts). */
  NV.palettes = {
    viridis: ["#440154", "#482878", "#3e4989", "#31688e", "#26828e",
              "#1f9e89", "#35b779", "#6ece58", "#b5de2b", "#fde725"],
    divergente: ["#b2182b", "#d6604d", "#f4a582", "#fddbc7", "#f7f7f7",
                 "#d1e5f0", "#92c5de", "#4393c3", "#2166ac"]
  };

  /** Couleur d'un score 0–100 ; null si la valeur manque. */
  NV.couleurScore = function (v, palette) {
    if (v == null || v === "" || !isFinite(v)) return null;
    return interpoler(NV.palettes[palette || "viridis"], Number(v) / 100);
  };

  /*
   * Carte bivariée 5 × 5 : classe de A en abscisse, de B en ordonnée,
   * couleur interpolée entre les quatre coins (bas-bas, A haut, B haut,
   * tous deux hauts). Même lecture que la légende 5 × 5 de nemeton.
   */
  NV.bivarie = {
    coins: { bb: "#e8e8e8", ah: "#5ac8c8", bh: "#be64ac", hh: "#3b4994" },
    classe: function (v) {
      if (v == null || !isFinite(v)) return null;
      return Math.min(4, Math.floor(Number(v) / 20));
    },
    couleur: function (ca, cb) {
      if (ca == null || cb == null) return null;
      var c = NV.bivarie.coins;
      var bas = hexRgb(interpoler([c.bb, c.ah], ca / 4)), haut = hexRgb(interpoler([c.bh, c.hh], ca / 4));
      return interpoler([rgbHex(bas), rgbHex(haut)], cb / 4);
    }
  };

  /** Texte lisible (clair ou sombre) sur un fond donné. */
  NV.contraste = function (fond) {
    var c = hexRgb(fond);
    var l = (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]) / 255;
    return l > 0.55 ? "#14201a" : "#ffffff";
  };

  /* ------------------------------------------------------------ carte */

  /**
   * Carte Leaflet sans fond tuilé. Les couches vectorielles passent par le
   * rendu SVG pour pouvoir utiliser le motif de hachures des valeurs
   * manquantes (fillColor: "url(#nv-hachures)").
   */
  NV.carte = function (el, options) {
    var carte = L.map(el, Object.assign({
      zoomSnap: 0.25,
      zoomDelta: 0.5,
      preferCanvas: false,
      attributionControl: true,
      boxZoom: false
    }, options || {}));
    carte.attributionControl.setPrefix(false);
    carte.createPane("reperes").style.zIndex = 350;
    carte.createPane("contexte").style.zIndex = 360;
    carte.createPane("surlignage").style.zIndex = 450;
    return carte;
  };

  /** Ajoute (une fois) le motif de hachures dans le SVG du rendu Leaflet. */
  NV.motifHachures = function (carte) {
    var svg = carte.getPanes().overlayPane.querySelector("svg");
    if (!svg || svg.querySelector("#nv-hachures")) return;
    var ns = "http://www.w3.org/2000/svg";
    var defs = document.createElementNS(ns, "defs");
    var p = document.createElementNS(ns, "pattern");
    p.setAttribute("id", "nv-hachures");
    p.setAttribute("patternUnits", "userSpaceOnUse");
    p.setAttribute("width", "7");
    p.setAttribute("height", "7");
    p.setAttribute("patternTransform", "rotate(45)");
    var fond = document.createElementNS(ns, "rect");
    fond.setAttribute("width", "7"); fond.setAttribute("height", "7");
    fond.setAttribute("fill", NV.css("--nv-manquant-fond") || "#d9dcd6");
    var l = document.createElementNS(ns, "line");
    l.setAttribute("x1", "0"); l.setAttribute("y1", "0");
    l.setAttribute("x2", "0"); l.setAttribute("y2", "7");
    l.setAttribute("stroke", NV.css("--nv-manquant-trait") || "#8a9088");
    l.setAttribute("stroke-width", "2");
    p.appendChild(fond); p.appendChild(l); defs.appendChild(p);
    svg.insertBefore(defs, svg.firstChild);
  };

  /** Couche de repère (contour communal, sections, contexte) non interactive. */
  NV.repere = function (carte, geojson, style, pane) {
    if (!geojson) return null;
    return L.geoJSON(geojson, {
      pane: pane || "reperes",
      interactive: false,
      style: function (f) { return typeof style === "function" ? style(f) : style; }
    }).addTo(carte);
  };

  /** Style du fond de contexte BD TOPO selon la propriété `couche`. */
  NV.styleContexte = function (f) {
    var c = f.properties && f.properties.couche;
    if (c === "plan_eau") return { color: NV.css("--nv-eau"), weight: 0.5, fillColor: NV.css("--nv-eau"), fillOpacity: 0.35 };
    if (c === "cours_eau") return { color: NV.css("--nv-eau"), weight: 1.4, opacity: 0.9 };
    var imp = Number(f.properties && f.properties.importance) || 5;
    return { color: NV.css("--nv-route"), weight: imp <= 2 ? 2.2 : imp <= 4 ? 1.3 : 0.7, opacity: 0.8 };
  };

  /* ------------------------------------------------------------ radar */

  /**
   * Radar SVG à n axes. series : [{valeurs: [0–100 | null], classe}].
   * Les valeurs manquantes ne sont pas tracées à zéro : le point est omis et
   * l'axe est marqué « manquant ».
   */
  NV.radar = function (el, axes, series, options) {
    options = options || {};
    var taille = options.taille || 300, cx = taille / 2, cy = taille / 2;
    var r = taille / 2 - (options.marge || 46), n = axes.length;
    var ns = "http://www.w3.org/2000/svg";
    function pt(i, v) {
      var a = -Math.PI / 2 + (2 * Math.PI * i) / n;
      return [cx + Math.cos(a) * r * v / 100, cy + Math.sin(a) * r * v / 100];
    }
    var h = [];
    h.push('<svg xmlns="' + ns + '" viewBox="0 0 ' + taille + " " + taille + '" role="img" class="nv-radar">');
    if (options.titre) h.push("<title>" + NV.echapper(options.titre) + "</title>");
    [20, 40, 60, 80, 100].forEach(function (g) {
      var pts = axes.map(function (_, i) { return pt(i, g).join(","); }).join(" ");
      h.push('<polygon class="nv-radar__grille" points="' + pts + '"/>');
    });
    axes.forEach(function (ax, i) {
      var p = pt(i, 100), q = pt(i, 116);
      var ancre = Math.abs(q[0] - cx) < 4 ? "middle" : q[0] > cx ? "start" : "end";
      var manque = series.length && series.every(function (s) { return s.valeurs[i] == null; });
      h.push('<line class="nv-radar__axe" x1="' + cx + '" y1="' + cy + '" x2="' + p[0] + '" y2="' + p[1] + '"/>');
      h.push('<text class="nv-radar__label' + (manque ? " nv-radar__label--manquant" : "") +
        '" x="' + q[0] + '" y="' + q[1] + '" text-anchor="' + ancre + '" dominant-baseline="middle">' +
        NV.echapper(ax.court || ax.label) + "</text>");
    });
    series.forEach(function (s) {
      var pts = [];
      s.valeurs.forEach(function (v, i) { if (v != null && isFinite(v)) pts.push(pt(i, v)); });
      if (pts.length > 2) {
        h.push('<polygon class="nv-radar__serie ' + (s.classe || "") + '" points="' +
          pts.map(function (p) { return p.join(","); }).join(" ") + '"/>');
      }
      pts.forEach(function (p) {
        h.push('<circle class="nv-radar__point ' + (s.classe || "") + '" cx="' + p[0] + '" cy="' + p[1] + '" r="2.6"/>');
      });
    });
    h.push("</svg>");
    el.innerHTML = h.join("");
  };

  /* ------------------------------------------------------------ capacités */

  /** Résout une capacité d'artéfact, ou null hors de claude.ai. */
  NV.capacite = function (nom) {
    try {
      if (global.claude && typeof global.claude.use === "function") {
        return global.claude.use(nom).catch(function () { return null; });
      }
    } catch (e) { /* hors viewer */ }
    return Promise.resolve(null);
  };

  /** Nom du serveur MCP local déclaré par le plugin (.mcp.json → "nemeton"). */
  NV.SERVEUR = "host:nemeton";

  var messagesMcp = {
    server_not_connected: "mcp_non_connecte",
    needs_reauth: "mcp_reauth",
    not_in_manifest: "mcp_refuse",
    not_granted: "mcp_refuse",
    blocked_by_policy: "mcp_politique",
    approval_required: "mcp_politique",
    cancelled: "mcp_annule",
    server_unavailable: "mcp_indisponible",
    selection_required: "mcp_non_connecte"
  };

  /** Message lisible pour une erreur de la capacité mcp. */
  NV.messageMcp = function (err) {
    if (err && err.nemeton) return err.message;
    var code = err && err.code;
    if (code === "tool_error") return NV.t("mcp_erreur_outil", { message: err.message || "" });
    return NV.t(messagesMcp[code] || "mcp_erreur", { code: code || "?" });
  };

  /**
   * Appelle un outil du connecteur nemeton. Rend le JSON de l'outil quand
   * `ok` est vrai ; rejette avec {nemeton: true, classe, message, candidats}
   * quand l'outil répond `ok: false`, ou avec l'erreur de la capacité.
   */
  NV.appeler = function (mcp, outil, entree, options) {
    return mcp.callTool(NV.SERVEUR, outil, entree, options).then(function (res) {
      var p = res && res.payload;
      if (typeof p === "string") { try { p = JSON.parse(p); } catch (e) { /* texte brut */ } }
      if (p && p.ok === false) {
        var err = new Error(p.erreur || "erreur");
        err.nemeton = true; err.classe = p.classe; err.candidats = p.candidats;
        throw err;
      }
      return p;
    });
  };

  /** Copie dans le presse-papiers, avec repli sur la sélection du texte. */
  NV.copier = function (texte, zone) {
    try {
      return navigator.clipboard.writeText(texte).then(function () { return true; }, function () {
        if (zone) { zone.focus(); zone.select(); }
        return false;
      });
    } catch (e) {
      if (zone) { zone.focus(); zone.select(); }
      return Promise.resolve(false);
    }
  };

  /** Petit message temporaire dans un élément [role=status]. */
  NV.annoncer = function (el, texte, duree) {
    if (!el) return;
    el.textContent = texte;
    clearTimeout(el._nvMinuteur);
    if (duree !== 0) el._nvMinuteur = setTimeout(function () { el.textContent = ""; }, duree || 4000);
  };

  NV.mouvementReduit = function () {
    try { return global.matchMedia("(prefers-reduced-motion: reduce)").matches; } catch (e) { return false; }
  };

  NV.textes({
    fr: {
      mcp_non_connecte: "Le connecteur nemeton ne répond pas ici : ouvrez cette vue dans l'application Claude de bureau où le serveur nemeton est installé.",
      mcp_reauth: "Reconnectez le connecteur nemeton dans Réglages → Connecteurs.",
      mcp_refuse: "L'accès au connecteur nemeton n'est pas autorisé pour cette vue. Vous pouvez l'activer dans le menu Autorisations de l'artéfact.",
      mcp_politique: "La politique de votre organisation bloque cet outil nemeton.",
      mcp_annule: "Appel annulé.",
      mcp_indisponible: "Le serveur nemeton ne répond pas pour le moment. Réessayez dans un instant.",
      mcp_erreur_outil: "nemeton a refusé l'opération : {message}",
      mcp_erreur: "Appel au connecteur nemeton en échec ({code})."
    },
    en: {
      mcp_non_connecte: "The nemeton connector does not answer here: open this view in the Claude desktop app where the nemeton server is installed.",
      mcp_reauth: "Reconnect the nemeton connector in Settings → Connectors.",
      mcp_refuse: "Access to the nemeton connector is not allowed for this view. You can turn it on in the artifact's Permissions menu.",
      mcp_politique: "Your organization's policy blocks this nemeton tool.",
      mcp_annule: "Call cancelled.",
      mcp_indisponible: "The nemeton server is not answering right now. Try again in a moment.",
      mcp_erreur_outil: "nemeton refused the operation: {message}",
      mcp_erreur: "Call to the nemeton connector failed ({code})."
    }
  });

  var langueMemorisee = NV.stockage.lire("nemeton-langue", null);
  if (langueMemorisee === "fr" || langueMemorisee === "en") NV.lang = langueMemorisee;

  global.NV = NV;
})(window);
