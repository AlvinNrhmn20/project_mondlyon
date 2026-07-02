import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncreal/core/constants/constants.dart';
import 'package:syncreal/shared/widgets/neon_widgets.dart';
import 'package:syncreal/shared/widgets/lucide_icons.dart';

class HobbyPickerSheet extends StatefulWidget {
  final List<String> initialSelectedHobbies;

  const HobbyPickerSheet({super.key, required this.initialSelectedHobbies});

  @override
  State<HobbyPickerSheet> createState() => _HobbyPickerSheetState();
}

class _HobbyPickerSheetState extends State<HobbyPickerSheet> {
  List<String> _allHobbies = [];
  List<String> _selectedHobbies = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedHobbies = List.from(widget.initialSelectedHobbies);
    _fetchAllHobbies();
  }

  Future<void> _fetchAllHobbies() async {
    try {
      final data = await Supabase.instance.client.from('hobbies').select('name');
      final List<dynamic> hobbiesList = data as List<dynamic>? ?? [];
      
      if (mounted) {
        setState(() {
          _allHobbies = hobbiesList.map((h) => h['name']?.toString() ?? '').where((name) => name.isNotEmpty).toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching all hobbies: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.black,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'SELECT HOBBIES',
                style: AppTheme.orbitron(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: 2,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.textSecondary),
                onPressed: () => Navigator.pop(context, widget.initialSelectedHobbies), // Cancel
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
          else if (_allHobbies.isEmpty)
            Text(
              'No hobbies found in database.',
              style: AppTheme.inter(color: AppColors.textSecondary),
            )
          else
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _allHobbies.map((h) {
                    final isSelected = _selectedHobbies.contains(h);
                    return NeonChip(
                      label: h,
                      color: isSelected ? Theme.of(context).colorScheme.primary : AppColors.textDisabled,
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
              ),
            ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: NeonOutlineButton(
              label: 'APPLY HOBBIES',
              icon: LucideIcons.check,
              color: Theme.of(context).colorScheme.primary,
              onTap: () {
                Navigator.pop(context, _selectedHobbies);
              },
            ),
          ),
        ],
      ),
    );
  }
}

