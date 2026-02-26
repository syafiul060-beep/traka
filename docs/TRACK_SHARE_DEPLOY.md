# Deploy Halaman Bagikan ke Keluarga

Fitur **Bagikan ke keluarga** membutuhkan halaman web `track.html` yang bisa diakses di browser.

## Catatan Penting

**Hosting di-deploy dari traka-admin** (bukan traka). Traka dan traka-admin memakai Firebase project yang sama (syafiul-traka). Deploy hosting dari traka-admin agar web admin dan track.html sama-sama tersedia.

## Langkah Deploy

### 1. Deploy Firestore rules (dari traka)

```bash
cd d:\Traka\traka
firebase deploy --only firestore:rules
```

### 2. Deploy hosting (dari traka-admin)

```bash
cd d:\Traka\traka-admin
npm run build
firebase deploy --only hosting
```

Atau gunakan script deploy:
```bash
cd d:\Traka\traka-admin
npm run deploy
```

### 3. URL setelah deploy

- Web Admin: `https://syafiul-traka.web.app/` atau `/dashboard`
- Lacak perjalanan: `https://syafiul-traka.web.app/track.html?t=TOKEN`

**PENTING:** Jangan deploy hosting dari folder `traka` — itu akan menimpa web admin. Selalu deploy dari `traka-admin`.
