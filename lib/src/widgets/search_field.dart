import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// The app's search input — a rounded glass field with a search icon. Submitting
/// (Enter, or the clear→retype flow) fires [onSubmitted] with the trimmed query.
/// Works with pointer and keyboard; on a TV a physical keyboard drives it.
class SearchField extends StatefulWidget {
  const SearchField({
    super.key,
    required this.onSubmitted,
    this.initialText = '',
    this.autofocus = false,
    this.hintText = 'Search for a movie or show…',
  });

  final ValueChanged<String> onSubmitted;
  final String initialText;
  final bool autofocus;
  final String hintText;

  @override
  State<SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<SearchField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _controller.text.trim();
    if (query.isNotEmpty) widget.onSubmitted(query);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      onSubmitted: (_) => _submit(),
      style: Theme.of(context).textTheme.bodyLarge,
      decoration: InputDecoration(
        isDense: true,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary),
        suffixIcon: IconButton(
          icon: const Icon(Icons.arrow_forward_rounded),
          tooltip: 'Search',
          onPressed: _submit,
        ),
        border: const OutlineInputBorder(
          borderRadius: AppRadii.rPill,
          borderSide: BorderSide(color: AppColors.glassStroke),
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: AppRadii.rPill,
          borderSide: BorderSide(color: AppColors.glassStroke),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: AppRadii.rPill,
          borderSide: BorderSide(color: AppColors.focus, width: 2),
        ),
      ),
    );
  }
}
