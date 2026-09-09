# INNOUS — Manufacturing Sourcing Platform (Prototype)

A single-file, front-end-only prototype of a B2B manufacturing sourcing platform connecting US industrial buyers with verified manufacturing partners in Mexico.

**Live demo:** enable via GitHub Pages (see below) or just open `index.html` in any browser — no build step, no backend, no dependencies beyond CDN-hosted fonts/icons.

## What it simulates

Three portals, switchable from the top bar ("Viewing as: Client / INNOUS / Supplier"):

- **Client** — submit an RFQ, track its status, review a shortlist of up to 5 manufacturing quotes, select one, and follow the order through production.
- **INNOUS** — the intermediary: review incoming RFQs, match and invite suppliers, compare supplier quotes side by side, apply a markup, build the customer shortlist, and manage orders, quality, logistics and analytics.
- **Supplier** — see only the RFQs INNOUS invites you to, submit quotes, and update production status on won orders.

Pricing confidentiality is enforced in the UI logic: suppliers never see INNOUS's markup or the customer's final price; customers never see the supplier's raw cost or identity.

All data is mock and held in memory (no backend). Refreshing the page resets the demo.

## Run locally

```bash
python3 -m http.server 8080
# open http://localhost:8080
```

Or just double-click `index.html`.
