# MedTrack 360 — Senior Project Presentation

**Presenters:** Roy Bilain & Jean-Paul
**Duration:** 10 minutes
**Slides:** 10 (≈ 1 minute each)

---

## Slide 1 — Title (30 seconds) — Roy

### On the slide
- **MedTrack 360**
- A unified medicine tracking system for Lebanese pharmacies
- Roy Bilain & Jean-Paul
- Senior Project — Computer Science

**[Add image: project logo or a Lebanese pharmacy photo]**

### What to say
> "Good [morning], everyone. We are Roy and Jean-Paul. Today we will present our senior project: **MedTrack 360**. It is a complete system that connects three groups — patients, pharmacies, and the Ministry of Public Health — into one platform that tracks every medicine in the country, in real time."

---

## Slide 2 — The Problem (60 seconds) — Roy

### On the slide
**The medication crisis in Lebanon today:**
- Patients visit many pharmacies just to find one medicine
- Some pharmacies sell above the Ministry's regulated price
- Hoarding makes shortages worse
- The Ministry has **no real-time view** of the supply chain
- New medicines wait weeks for paper-based approval

**[Add image: empty pharmacy shelf or news headline]**

### What to say
> "Anyone living in Lebanon today knows the problem. A patient can walk into five pharmacies and still not find their medicine. Some pharmacies sell above the price the Ministry has set. Others hoard medicines and make the shortage worse. And the Ministry itself — the regulator — has very little real-time data to make decisions. Even the simple process of approving a new medicine can take weeks. We built MedTrack 360 to fix this with technology."

---

## Slide 3 — Our Solution: Three Apps, One Brain (60 seconds) — Roy

### On the slide
```
   📱 Citizen App        💼 POS App         🖥️ Ministry Dashboard
     (Flutter)           (Flutter)              (React)
          \                 |                      /
           \                |                     /
            \               |                    /
                 🌐 Node.js + Express APIs
                         |
                 ☁️ Neon PostgreSQL
                  (one shared database)
```
- **One database** — every action visible to everyone who should see it
- **Real-time sync** — a sale at a pharmacy updates the Ministry dashboard in seconds
- **Built for Lebanon** — real pharmacies, real Ministry pricing, real medicines

**[Add image: architecture diagram screenshot]**

### What to say
> "Our solution has three applications that all talk to a single cloud database. The citizen has a mobile app to find medicines. The pharmacy has a Point-of-Sale app for the counter. The Ministry has a web dashboard for oversight. All three are powered by one shared database hosted on Neon. The result: every sale, every price change, every new medicine — is immediately visible to anyone who needs to see it."

---

## Slide 4 — The Citizen App (90 seconds) — Roy

### On the slide
**For the public — find medicines, anywhere, fast.**
- 🔍 Search by name or barcode
- 📍 See which nearby pharmacies have it in stock
- 💵 Compare each pharmacy's price to the official Ministry price
- ❤️ Watchlist + notifications when out-of-stock medicines return
- 🗺️ Pharmacy map with live availability
- 📰 Reads health news pushed by the Ministry

Built with **Flutter** — same codebase runs on iOS, Android, and web.

**[Add image: 2 or 3 screenshots — search screen, pharmacy list, map view]**

### What to say
> "The citizen app is the public face of the system. A patient opens the app, searches for 'Panadol', and sees every nearby pharmacy that has it, the exact stock level, and the price. Next to each price, we show the official Ministry-fixed price — so the citizen immediately knows if they are being charged fairly. They can save medicines to a personal watchlist, and the app notifies them when a nearby pharmacy restocks. The app also shows pharmacies on a real map. It's built with Flutter, which means one codebase runs on iPhone, Android, and even the web."

---

## Slide 5 — The POS App for Pharmacies (90 seconds) — Jean-Paul

### On the slide
**For pharmacy staff — modern POS + smart inventory.**
- 💼 Record sales and purchases at the counter
- 📊 Real-time inventory updates after every sale
- 🚨 Low-stock alerts and expiry warnings
- 📤 Submit new medicines for Ministry approval — directly from the app
- 🔄 **Works offline** — local SQLite database, syncs when online
- 📰 Receives Ministry announcements

Built with **Flutter** + offline-first design.

**[Add image: 2 or 3 POS screenshots — inventory, sales, add-medicine dialog]**

### What to say
> "The POS app is what pharmacy staff use every day, just like a cash register. They scan a barcode, record the sale, and the inventory updates automatically. If stock drops too low, the app warns them. If they want to add a new medicine that isn't in the national registry yet, they can submit a request directly from the app to the Ministry — no paperwork. And one detail we're very proud of: the POS works **offline**. In rural areas where internet can be unstable, the pharmacy keeps selling, and when the connection comes back, everything syncs to the cloud automatically. We use a local SQLite database for this."

---

## Slide 6 — The Ministry Dashboard (90 seconds) — Jean-Paul

### On the slide
**For the Ministry of Public Health — full visibility, real-time control.**
- 📊 **Stock Oversight** — live inventory across every pharmacy
- ⚠️ **Compliance Monitoring** — automatic flags for price violations and hoarding
- 🆕 **Governance Inbox** — approve or reject new medicines from pharmacies (with a live badge counter)
- 📡 **Sync Health** — which pharmacies are online and synced
- 📰 **Announcements** — push health news to every pharmacy POS in one click
- 🏥 **Master Registry** — central control of every licensed pharmacy and every medicine

Built with **React + Vite** for a fast, professional admin experience.

**[Add image: 2 or 3 dashboard screenshots — compliance page, governance inbox, registry]**

### What to say
> "The Ministry dashboard is where inspectors and supervisors do their job. In one screen, they see every medicine, every pharmacy, every transaction across the country. The compliance page automatically detects pharmacies selling above the ceiling price, or pharmacies hoarding stock with very few sales — without any human inspector visiting them. When a pharmacy submits a new medicine, it appears in the Governance Inbox with a notification badge. The admin reviews and approves it with one click — and the new medicine instantly appears in every citizen's app. The Ministry can also broadcast news — for example, a flu vaccine campaign — to every pharmacy in the country in real time."

---

## Slide 7 — Architecture & Tech Stack (60 seconds) — Jean-Paul

### On the slide
**Modern, professional, scalable.**

| Layer | Technology |
|---|---|
| Mobile apps (citizen + POS) | Flutter 3 (Dart) |
| Web dashboard | React 19 + Vite |
| Backend APIs | Node.js + Express |
| Database | PostgreSQL on Neon (serverless cloud) |
| Offline storage | SQLite (sqflite) |
| Real-time sync | REST APIs + database triggers |

**Why this matters:**
- One Flutter codebase = iOS + Android + Web
- Neon scales the database automatically — no servers to manage
- Secure HTTP authentication between every component

**[Add image: tech logos or stack diagram]**

### What to say
> "We chose tools that are modern and used by real companies — not just for learning. Flutter lets us build the citizen app and the POS app from one codebase. React with Vite gives the dashboard a fast, smooth experience. The Node and Express backends serve our REST APIs. The database is PostgreSQL hosted on Neon — it's serverless, which means it scales automatically with no servers for us to manage. And everywhere, we use secure HTTP authentication, so only the right people can access the right data."

---

## Slide 8 — One Database, One Source of Truth (60 seconds) — Roy

### On the slide
**40 tables. One cloud database. All three apps connected.**

Key tables we built:
- `pharmacies` — every licensed pharmacy
- `moph_registry` — the official medicine catalog
- `inventory_movements` — every purchase and sale, ever
- `pharmacy_stock` — per-pharmacy live stock
- `medicine_registration_requests` — pending Ministry approvals
- `health_news` — Ministry broadcasts

**The smart part:** automatic Postgres triggers
- A pharmacy sells one Panadol →
- `inventory_movements` gets one new row →
- Trigger fires → `pharmacy_stock.stock_units` drops by 1, **national total** drops by 1
- All three apps see the new number instantly

**[Add image: Neon dashboard screenshot or database schema diagram]**

### What to say
> "Behind everything is one PostgreSQL database with 40 tables. The most important table is `inventory_movements` — every sale or purchase is one row. We wrote a smart database trigger: every time a sale happens, the trigger automatically updates that pharmacy's stock, the national total, and even the medicine's availability flag. This means our three apps don't have to coordinate manually — the database itself keeps everything consistent. It's what gives the whole system its real-time feel."

---

## Slide 9 — What Makes MedTrack 360 Special (90 seconds) — Jean-Paul

### On the slide
**Seven strong features that set this project apart:**

1. **One unified ecosystem** — citizens, pharmacies, and Ministry on the same data
2. **Automatic compliance detection** — no manual inspections needed
3. **Offline-first POS** — works without internet, syncs when online
4. **Real Lebanese data** — 24 pharmacies, MoPH-aligned medicine list
5. **One-click medicine approval workflow** — pharmacies submit, Ministry approves, citizens see it
6. **Cross-platform reach** — phones, browsers, and desktop
7. **Scalable cloud architecture** — ready for hundreds of pharmacies

**[Add image: collage of all three apps side by side]**

### What to say
> "What makes MedTrack 360 special is not any single feature — it's how all the pieces work together. A patient in Beirut searches for Panadol. The app shows Al-Amin Pharmacy has 130 units at the regulated price. Meanwhile, Al-Amin's staff just sold 5 boxes using the POS. The Ministry dashboard already shows the updated count and confirms that the price is in compliance. All of this happens in seconds, automatically, with no human pushing buttons. We are not just connecting screens — we are connecting **decisions** between citizens, businesses, and the government in real time. That is what makes this project strong, useful, and unique."

---

## Slide 10 — Closing & Demo (30 seconds) — Roy & Jean-Paul

### On the slide
**MedTrack 360**

**Thank you.**

We're ready for a live demo and your questions.

GitHub: `github.com/roybilain1/MedTrack360`

**[Add image: team photo or simple logo]**

### What to say
> "Thank you for listening. We're happy to take any questions, and we can give you a live demo of any of the three applications you'd like to see."

---

# Speaker time budget

| Slide | Speaker | Seconds | Cumulative |
|---|---|---|---|
| 1. Title | Roy | 30 | 0:30 |
| 2. Problem | Roy | 60 | 1:30 |
| 3. Solution overview | Roy | 60 | 2:30 |
| 4. Citizen app | Roy | 90 | 4:00 |
| 5. POS app | Jean-Paul | 90 | 5:30 |
| 6. Ministry dashboard | Jean-Paul | 90 | 7:00 |
| 7. Tech stack | Jean-Paul | 60 | 8:00 |
| 8. Database | Roy | 60 | 9:00 |
| 9. Strong features | Jean-Paul | 90 | 10:30 |
| 10. Closing | Both | 30 | 11:00 |

If 11 minutes is too long, cut slide 9 to 60 seconds (drop 2 of the 7 bullet points). Total = 10:00.

---

# Image placement guide

You'll add 2–3 screenshots per app slide. Suggested choices:

- **Slide 1**: A clean MedTrack logo or a Lebanese pharmacy photo
- **Slide 2**: News headline about Lebanese pharma crisis OR empty pharmacy shelf
- **Slide 3**: Architecture diagram (3 apps + database)
- **Slide 4** (Citizen app): Search screen, pharmacy list with prices, map view
- **Slide 5** (POS app): Inventory screen, sales/checkout, add-medicine dialog
- **Slide 6** (Ministry): Compliance Monitoring tab, Governance Inbox, Master Registry
- **Slide 7**: Tech stack logos (Flutter, React, Node, PostgreSQL, Neon)
- **Slide 8**: Neon console showing tables OR a database ER diagram
- **Slide 9**: All three apps side by side
- **Slide 10**: Team photo or final logo

---

# Tips for delivery

1. **Practice once with a timer.** Reading the speaker notes aloud should take exactly the times shown above. Don't read from the slides themselves — they're just visual support.
2. **Keep eye contact** with the audience, especially during the "Why this is special" parts.
3. **Slow down at slide 8 (the trigger explanation)** — that is the strongest technical detail. Let it land.
4. **Hand off cleanly between speakers** — agree on a phrase like "and now Jean-Paul will show you how the pharmacy uses the system" so the audience knows there's a transition.
5. **If asked a hard question**, it's okay to say: "Great question — let me show you in the demo." Then demo the relevant screen.

Good luck! 🎓
