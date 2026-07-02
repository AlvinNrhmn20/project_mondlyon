import 'package:flutter/material.dart';
import 'package:syncreal/core/constants/constants.dart';
import 'package:syncreal/shared/widgets/lucide_icons.dart';

class EditTextFields extends StatelessWidget {
  final TextEditingController fullNameController;
  final TextEditingController bioController;
  final TextEditingController locationController;
  final TextEditingController educationController;
  final TextEditingController workController;
  final String? selectedAstrologicalSign;
  final ValueChanged<String?> onAstrologicalSignChanged;

  static const List<String> _zodiacSigns = [
    'Aries', 'Taurus', 'Gemini', 'Cancer',
    'Leo', 'Virgo', 'Libra', 'Scorpio',
    'Sagittarius', 'Capricorn', 'Aquarius', 'Pisces',
  ];

  static const Map<String, String> _zodiacEmoji = {
    'Aries': '♈', 'Taurus': '♉', 'Gemini': '♊', 'Cancer': '♋',
    'Leo': '♌', 'Virgo': '♍', 'Libra': '♎', 'Scorpio': '♏',
    'Sagittarius': '♐', 'Capricorn': '♑', 'Aquarius': '♒', 'Pisces': '♓',
  };

  const EditTextFields({
    super.key,
    required this.fullNameController,
    required this.bioController,
    required this.locationController,
    required this.educationController,
    required this.workController,
    required this.selectedAstrologicalSign,
    required this.onAstrologicalSignChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // --- FULL NAME ---
        _buildLabel(context, 'FULL NAME', LucideIcons.user),
        const SizedBox(height: 12),
        TextField(
          controller: fullNameController,
          style: AppTheme.inter(color: AppColors.textPrimary),
          decoration: _inputDecoration(context, 'Enter your full name'),
        ),

        const SizedBox(height: 24),

        // --- BIO ---
        _buildLabel(context, 'BIO', LucideIcons.info),
        const SizedBox(height: 12),
        TextField(
          controller: bioController,
          maxLines: 4,
          style: AppTheme.inter(color: AppColors.textPrimary),
          decoration: _inputDecoration(context, 'Write a short bio...'),
        ),

        const SizedBox(height: 24),

        // --- LOCATION ---
        _buildLabel(context, 'LOCATION', LucideIcons.mapPin),
        const SizedBox(height: 12),
        TextField(
          controller: locationController,
          style: AppTheme.inter(color: AppColors.textPrimary),
          decoration: _inputDecoration(context, 'e.g. Jakarta, Indonesia'),
        ),

        const SizedBox(height: 24),

        // --- EDUCATION ---
        _buildLabel(context, 'EDUCATION', LucideIcons.bookOpen),
        const SizedBox(height: 12),
        TextField(
          controller: educationController,
          style: AppTheme.inter(color: AppColors.textPrimary),
          decoration: _inputDecoration(context, 'e.g. Universitas Indonesia'),
        ),

        const SizedBox(height: 24),

        // --- WORK ---
        _buildLabel(context, 'WORK', LucideIcons.briefcase),
        const SizedBox(height: 12),
        TextField(
          controller: workController,
          style: AppTheme.inter(color: AppColors.textPrimary),
          decoration: _inputDecoration(context, 'e.g. Software Engineer at Google'),
        ),

        const SizedBox(height: 24),

        // --- ASTROLOGICAL SIGN ---
        _buildLabel(context, 'ASTROLOGICAL SIGN', LucideIcons.star),
        const SizedBox(height: 12),
        _buildZodiacDropdown(context),
      ],
    );
  }

  Widget _buildZodiacDropdown(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedAstrologicalSign,
          hint: Text(
            'Select your zodiac sign',
            style: AppTheme.inter(color: AppColors.textDisabled),
          ),
          isExpanded: true,
          dropdownColor: AppColors.surfaceCard,
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: Theme.of(context).colorScheme.primary),
          style: AppTheme.inter(color: AppColors.textPrimary),
          onChanged: onAstrologicalSignChanged,
          items: _zodiacSigns.map((sign) {
            final emoji = _zodiacEmoji[sign] ?? '';
            return DropdownMenuItem<String>(
              value: sign,
              child: Row(
                children: [
                  Text(
                    emoji,
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    sign,
                    style: AppTheme.inter(color: AppColors.textPrimary),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text, LucideIconData icon) {
    return Row(
      children: [
        LucideIcon(icon: icon, color: Theme.of(context).colorScheme.primary, size: 18),
        const SizedBox(width: 8),
        Text(
          text,
          style: AppTheme.orbitron(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.textSecondary,
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(BuildContext context, String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: AppTheme.inter(color: AppColors.textDisabled),
      filled: true,
      fillColor: AppColors.surfaceCard,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 1.5),
      ),
    );
  }
}
