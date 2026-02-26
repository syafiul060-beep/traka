# Menghapus File .hprof dari Git History

File heap dump Java (`.hprof`) berukuran besar ada di history Git. Ikuti langkah berikut:

## Opsi 1: Menggunakan BFG Repo-Cleaner (Disarankan)

1. **Download BFG:** https://rtyley.github.io/bfg-repo-cleaner/
   - Download `bfg.jar`

2. **Jalankan di folder traka:**
   ```bash
   cd d:\Traka\traka
   java -jar path\to\bfg.jar --delete-files "*.hprof"
   git reflog expire --expire=now --all
   git gc --prune=now --aggressive
   git push -f origin master
   git push origin master:main
   ```

## Opsi 2: Menggunakan git filter-branch

Jalankan di **Git Bash** (bukan CMD):

```bash
cd /d/Traka/traka

git filter-branch --force --index-filter \
  "git rm -rf --cached --ignore-unmatch \
    android/java_pid5100.hprof \
    android/Java_pid12608.hprof \
    android/Java_pid1856.hprof" \
  --prune-empty --tag-name-filter cat -- --all

git push -f origin master
git push origin master:main
```

## Opsi 3: Fresh Start (Paling Sederhana)

Jika history tidak penting, buat repo baru:

1. **Backup** folder `traka` (copy ke tempat lain)
2. **Hapus** folder `.git` di dalam traka
3. **Pastikan** file .hprof TIDAK ada di folder android (hapus jika ada)
4. **Init ulang:**
   ```bash
   cd d:\Traka\traka
   del /s /q android\*.hprof 2>nul
   rmdir /s /q .git
   git init
   git add .
   git commit -m "Initial commit - clean"
   git remote add origin https://github.com/syafiul060-beep/traka.git
   git push -f -u origin master
   git push origin master:main
   ```

**Catatan Opsi 3:** Semua history commit akan hilang. Hanya gunakan jika opsi 1 dan 2 gagal.
