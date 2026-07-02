import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncreal/core/constants/constants.dart';
import 'package:syncreal/shared/widgets/lucide_icons.dart';
import 'package:syncreal/shared/widgets/neon_widgets.dart';
import 'widgets/edit_text_fields.dart';
import 'widgets/hobby_picker_sheet.dart';

class EditProfilePage extends StatefulWidget {
  const EditProfilePage({super.key});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _bioController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _educationController = TextEditingController();
  final TextEditingController _workController = TextEditingController();
  String? _selectedAstrologicalSign;
  
  List<String> _selectedHobbies = [];
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchCurrentProfileData();
  }

  Future<void> _fetchCurrentProfileData() async {
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // 1. Fetch Profile
      final data = await Supabase.instance.client
          .from('profiles')
          .select('full_name, bio, location, education, work, astrological_sign')
          .eq('id', user.id)
          .single();

      // 2. Fetch User Hobbies
      final userHobbiesData = await Supabase.instance.client
          .from('user_hobbies')
          .select('hobby_id')
          .eq('user_id', user.id);

      final List<dynamic> uhList = userHobbiesData as List<dynamic>? ?? [];
      final List<dynamic> hobbyIds = uhList.map((uh) => uh['hobby_id']).toList();

      List<String> fetchedHobbies = [];
      if (hobbyIds.isNotEmpty) {
        final hobbiesData = await Supabase.instance.client
            .from('hobbies')
            .select('name')
            .inFilter('id', hobbyIds);

        final List<dynamic> hList = hobbiesData as List<dynamic>? ?? [];
        fetchedHobbies = hList.map((h) => h['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      }

      if (mounted) {
        setState(() {
          _fullNameController.text = data['full_name']?.toString() ?? '';
          _bioController.text = data['bio']?.toString() ?? '';
          _locationController.text = data['location']?.toString() ?? '';
          _educationController.text = data['education']?.toString() ?? '';
          _workController.text = data['work']?.toString() ?? '';
          _selectedAstrologicalSign = data['astrological_sign']?.toString();
          _selectedHobbies = fetchedHobbies;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching edit profile data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _saveProfileData() async {
    setState(() => _isSaving = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;

      // a. Update profiles
      await Supabase.instance.client.from('profiles').update({
        'full_name': _fullNameController.text.trim(),
        'bio': _bioController.text.trim(),
        'location': _locationController.text.trim(),
        'education': _educationController.text.trim(),
        'work': _workController.text.trim(),
        'astrological_sign': _selectedAstrologicalSign,
      }).eq('id', user.id);

      // b. Delete old relations
      await Supabase.instance.client
          .from('user_hobbies')
          .delete()
          .eq('user_id', user.id);

      // c & d. Fetch new hobby IDs and insert
      if (_selectedHobbies.isNotEmpty) {
        final hobbiesData = await Supabase.instance.client
            .from('hobbies')
            .select('id')
            .inFilter('name', _selectedHobbies);
            
        final List<dynamic> hData = hobbiesData as List<dynamic>? ?? [];
        if (hData.isNotEmpty) {
          final List<Map<String, dynamic>> inserts = hData.map((h) {
            return {
              'user_id': user.id,
              'hobby_id': h['id'],
            };
          }).toList();
          
          await Supabase.instance.client.from('user_hobbies').insert(inserts);
        }
      }

      // e. Go back to profile page
      if (mounted) {
        Navigator.pop(context, true); // true indicates successful update
      }

    } catch (e) {
      debugPrint('Error saving profile data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _openHobbyPicker() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: HobbyPickerSheet(initialSelectedHobbies: _selectedHobbies),
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedHobbies = result;
      });
    }
  }

@override
  void dispose() {
    _fullNameController.dispose();
    _bioController.dispose();
    _locationController.dispose();
    _educationController.dispose();
    _workController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      appBar: AppBar(
        backgroundColor: AppColors.black,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'EDIT PROFILE',
          style: AppTheme.orbitron(fontSize: 14, color: AppColors.textPrimary, letterSpacing: 2),
        ),
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(color: AppColors.neonGreen, strokeWidth: 2),
              ),
            )
          else
            TextButton(
              onPressed: _saveProfileData,
              child: Text(
                'SAVE',
                style: AppTheme.inter(color: AppColors.neonGreen, fontWeight: FontWeight.bold),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.divider),
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  EditTextFields(
                    fullNameController: _fullNameController,
                    bioController: _bioController,
                    locationController: _locationController,
                    educationController: _educationController,
                    workController: _workController,
                    selectedAstrologicalSign: _selectedAstrologicalSign,
                    onAstrologicalSignChanged: (value) {
                      setState(() => _selectedAstrologicalSign = value);
                    },
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const LucideIcon(icon: LucideIcons.sparkles, color: AppColors.neonCyan, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'HOBBIES',
                            style: AppTheme.orbitron(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textSecondary,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: Icon(Icons.edit, color: Theme.of(context).colorScheme.primary, size: 20),
                        onPressed: _openHobbyPicker,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (_selectedHobbies.isEmpty)
                    Text('No hobbies selected.', style: AppTheme.inter(color: AppColors.textDisabled))
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _selectedHobbies.map((h) {
                        return NeonChip(
                          label: h,
                          color: AppColors.neonCyan,
                          onTap: _openHobbyPicker,
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
    );
  }
}

