🕒 Phase 2: FOMO Engine, Onboarding & Personalization
Status: Sprint 1 DONE ✅ | Sprint Target: FOMO Logic & User Education

1. 🧪 User-Triggered FOMO Engine (The Core)
[✅] 1-Hour Sync Window: Implementasi logika 'Start-on-First-Open'. Simpan timestamp window_opened_at di Supabase saat user pertama kali buka kamera.

[✅] Daily Reset Logic: Reset jatah 1 jam setiap hari (cek pergantian tanggal pada record).

[✅] Floating Countdown UI: Buat widget timer melayang (Floating UI) di atas Home Feed dengan desain glassmorphism.

[✅] 24-Hour Feed Filter: Modifikasi query Home Feed agar hanya menampilkan postingan yang berumur kurang dari 24 jam (FOMO Feed).

[✅] Profile Memories: Pastikan postingan lama tetap muncul di halaman Profile user (Archived status) — query profile_page.dart tidak pakai filter 24 jam.

[ ] Strict Lockdown: Tidak ada bonus time. Jika waktu habis, tombol '+' dan akses kamera terkunci total hingga hari berikutnya.

2. 🎨 Dynamic Neon Accents (Personalization)
[x] Neon Theme Refactor: Modifikasi AppTheme agar warna aksen neon bisa diganti secara dinamis via State Management.

[x] Theme Switcher UI: Tambahkan preset warna neon di SettingsPage.

3. 🛠️ Future Refactoring (The 5% Debt)
[ ] Audio Player Cleanup: Gunakan WidgetsBindingObserver untuk auto-dispose GlobalAudioPlayer.

[ ] Post Item Modularization: Refactor home_page.dart menjadi komponen-komponen kecil yang lebih rapi.

Updated for Alvin Nurrahman — Lead Architect of SyncReal
