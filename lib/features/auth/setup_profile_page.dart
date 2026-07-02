// lib/features/auth/setup_profile_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/constants.dart';
import '../../shared/widgets/lucide_icons.dart';
import '../../shared/widgets/neon_widgets.dart';
import '../../main.dart'; // Untuk memanggil MainNavigationScreen()
import 'package:supabase_flutter/supabase_flutter.dart';

class SetupProfilePage extends StatefulWidget {
  const SetupProfilePage({super.key});

  @override
  State<SetupProfilePage> createState() => _SetupProfilePageState();
}

class DateTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    if (oldValue.text.length >= newValue.text.length) {
      return newValue;
    }
    final text = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (text.length > 8) return oldValue;
    var newText = '';
    for (int i = 0; i < text.length; i++) {
      newText += text[i];
      if ((i == 1 || i == 3) && i != text.length - 1) {
        newText += '/';
      }
    }
    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
  }
}

class _SetupProfilePageState extends State<SetupProfilePage> {
  final PageController _pageController = PageController();

  // ── Controllers ──
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _workController = TextEditingController();
  final TextEditingController _educationController = TextEditingController();

  final Set<String> _selectedHobbies = {};
  bool _isLoading = false;
  int _currentPage = 0;

  Future<void> _submitProfileData() async {
    setState(() => _isLoading = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        // Upsert profil dengan semua field termasuk yang baru
        await Supabase.instance.client.from('profiles').upsert({
          'id': user.id,
          'username': _usernameController.text.trim().replaceAll('@', ''),
          'dob': _dobController.text.trim(),
          'bio': _bioController.text.trim(),
          'location': _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          'work': _workController.text.trim().isEmpty
              ? null
              : _workController.text.trim(),
          'education': _educationController.text.trim().isEmpty
              ? null
              : _educationController.text.trim(),
        });

        // Hapus hobi lama lalu insert yang baru
        await Supabase.instance.client
            .from('user_hobbies')
            .delete()
            .eq('user_id', user.id);

        if (_selectedHobbies.isNotEmpty) {
          final List<dynamic> hobbyData = await Supabase.instance.client
              .from('hobbies')
              .select('id')
              .inFilter('name', _selectedHobbies.toList());

          if (hobbyData.isNotEmpty) {
            final List<Map<String, dynamic>> userHobbiesData =
                hobbyData.map((hobby) {
              return {
                'user_id': user.id,
                'hobby_id': hobby['id'],
              };
            }).toList();

            await Supabase.instance.client
                .from('user_hobbies')
                .insert(userHobbiesData);
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _nextPage() async {
    if (_isLoading) return;

    if (_currentPage < 2) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      // Fase Terakhir → Simpan data lalu masuk ke Main Dashboard
      await _submitProfileData();

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const MainNavigationScreen()),
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _usernameController.dispose();
    _dobController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _workController.dispose();
    _educationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Progress Indicator Neon ──
            Padding(
              padding: const EdgeInsets.only(top: 20, bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (index) {
                  final isActive = _currentPage == index;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 24 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive ? primary : AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: primary.withValues(alpha: 0.60),
                                blurRadius: 10,
                              )
                            ]
                          : null,
                    ),
                  );
                }),
              ),
            ),

            // ── PageView Forms ──
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) =>
                    setState(() => _currentPage = index),
                children: [
                  _buildIdentityPage(),
                  _buildHobbiesPage(),
                  _buildWelcomePage(),
                ],
              ),
            ),

            // ── Bottom Navigation / Next Button ──
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: NeonOutlineButton(
                  label: _isLoading
                      ? 'SYNCING...'
                      : (_currentPage == 2 ? 'ENTER THE VOID' : 'NEXT STEP'),
                  icon: _isLoading
                      ? LucideIcons.timer
                      : (_currentPage == 2
                          ? LucideIcons.zap
                          : LucideIcons.chevronRight),
                  color: _currentPage == 2 ? AppColors.neonGreen : primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  onTap: _nextPage,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── Fase 1: Identity ──
  // Dibungkus SingleChildScrollView agar tidak overflow saat keyboard muncul.
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildIdentityPage() {
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionLabel(
            label: 'INITIALIZE IDENTITY',
            icon: LucideIcons.user,
            accentColor: primary,
          ),
          const SizedBox(height: 32),

          // ── Username ──
          TextField(
            controller: _usernameController,
            style: AppTheme.inter(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Username (e.g. alvinnur)',
              prefixText: '@',
              prefixStyle: AppTheme.inter(
                color: primary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Date of Birth ──
          TextField(
            controller: _dobController,
            style: AppTheme.inter(color: AppColors.textPrimary),
            decoration:
                const InputDecoration(hintText: 'Date of Birth (DD/MM/YYYY)'),
            keyboardType: TextInputType.number,
            inputFormatters: [DateTextFormatter()],
          ),
          const SizedBox(height: 16),

          // ── Bio ──
          TextField(
            controller: _bioController,
            maxLines: 3,
            style: AppTheme.inter(color: AppColors.textPrimary),
            decoration:
                const InputDecoration(hintText: 'Write a short bio...'),
          ),
          const SizedBox(height: 24),

          // ── Divider label ──
          Row(
            children: [
              const Expanded(child: Divider(color: AppColors.divider)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OPTIONAL DETAILS',
                  style: AppTheme.orbitron(
                    fontSize: 9,
                    color: AppColors.textDisabled,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const Expanded(child: Divider(color: AppColors.divider)),
            ],
          ),
          const SizedBox(height: 20),

          // ── Location (Autocomplete) ──
          _buildAutocompleteField(
            label: 'Location',
            hint: 'e.g. Jakarta Selatan',
            icon: LucideIcons.mapPin,
            controller: _locationController,
            options: ProfileOptions.locationOptions,
            accentColor: primary,
          ),
          const SizedBox(height: 16),

          // ── Work (Autocomplete) ──
          _buildAutocompleteField(
            label: 'Work / Profession',
            hint: 'e.g. Software Engineer',
            icon: LucideIcons.briefcase,
            controller: _workController,
            options: ProfileOptions.workOptions,
            accentColor: primary,
          ),
          const SizedBox(height: 16),

          // ── Education (Autocomplete) ──
          _buildAutocompleteField(
            label: 'Education',
            hint: 'e.g. Universitas Bina Sarana Informatika',
            icon: LucideIcons.bookOpen,
            controller: _educationController,
            options: ProfileOptions.educationOptions,
            accentColor: primary,
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── Helper: Autocomplete Field dengan Hybrid Input ──
  //
  // Aturan Hybrid: Jika user mengetik teks bebas yang tidak ada di list,
  // teks tersebut tetap tersimpan di controller dan tidak terhapus.
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildAutocompleteField({
    required String label,
    required String hint,
    required LucideIconData icon,
    required TextEditingController controller,
    required List<String> options,
    required Color accentColor,
  }) {
    return Autocomplete<String>(
      // Saat user memilih opsi dari daftar, isi controller dengan nilai tersebut
      onSelected: (value) {
        controller.text = value;
      },
      // Filter: tampilkan opsi yang mengandung teks yang diketik (case-insensitive)
      optionsBuilder: (TextEditingValue textEditingValue) {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<String>.empty();
        }
        return options.where(
          (option) => option.toLowerCase().contains(
                textEditingValue.text.toLowerCase(),
              ),
        );
      },
      // Teks awal field diambil dari controller (mendukung pre-fill jika ada)
      initialValue: TextEditingValue(text: controller.text),
      // ── Styling dropdown item ──
      optionsViewBuilder: (context, onSelected, filteredOptions) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            color: AppColors.surfaceCard,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.divider),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: filteredOptions.length,
                itemBuilder: (context, index) {
                  final option = filteredOptions.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(
                        option,
                        style: AppTheme.inter(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
      // ── Styling input field ──
      fieldViewBuilder:
          (context, fieldController, focusNode, onFieldSubmitted) {
        // ── Hybrid Input: sinkronkan fieldController ↔ controller utama ──
        // Saat field kehilangan fokus, simpan apapun yang diketik user
        // (termasuk teks bebas yang tidak ada di list) ke controller utama.
        fieldController.addListener(() {
          controller.text = fieldController.text;
        });

        return TextField(
          controller: fieldController,
          focusNode: focusNode,
          style: AppTheme.inter(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            labelText: label,
            labelStyle: AppTheme.inter(color: AppColors.textSecondary, fontSize: 12),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: LucideIcon(
                icon: icon,
                color: accentColor,
                size: 18,
              ),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          ),
          onSubmitted: (_) => onFieldSubmitted(),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── Fase 2: Hobbies ──
  // Array hobbies dipindah ke ProfileOptions — UI tetap bersih.
  // ─────────────────────────────────────────────────────────────────────────
  // ✅ FIX P5: Dibungkus SingleChildScrollView — mencegah bottom overflow
  // saat jumlah hobi banyak dan layar kecil. Padding dipindah ke dalam scroll.
  Widget _buildHobbiesPage() {
    final primary = Theme.of(context).colorScheme.primary;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionLabel(
            label: 'SELECT YOUR NODES',
            icon: LucideIcons.sparkles,
            accentColor: AppColors.neonCyan,
          ),
          const SizedBox(height: 16),
          Text(
            'Pick at least 3 hobbies to sync with others.',
            style: AppTheme.inter(color: AppColors.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 32),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: ProfileOptions.hobbiesOptions.map((h) {
              final isSelected = _selectedHobbies.contains(h);
              return NeonChip(
                label: h,
                color: isSelected ? primary : AppColors.textDisabled,
                onTap: () {
                  setState(() {
                    if (isSelected) {
                      _selectedHobbies.remove(h);
                    } else {
                      _selectedHobbies.add(h);
                    }
                  });
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ── Fase 3: Welcome ──
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildWelcomePage() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const LucideIcon(
            icon: LucideIcons.activity,
            color: AppColors.neonGreen,
            size: 64,
          ),
          const SizedBox(height: 24),
          Text(
            'YOU ARE SYNCED',
            style: AppTheme.orbitron(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.neonGreen,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Your reality is now online.',
            style: AppTheme.inter(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}