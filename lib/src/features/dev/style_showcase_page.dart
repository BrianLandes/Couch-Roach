import 'package:flutter/material.dart';

import '../../theme/theme.dart';

/// Living component gallery for the liquid-glass design system. Reachable at
/// [Routes.styleShowcase]. Use it as the palette when building UI, and **add new
/// shared widgets here** as they land so the reference stays current.
class StyleShowcasePage extends StatelessWidget {
  const StyleShowcasePage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.screenPadding),
            children: [
              Text('Couch Roach', style: text.displaySmall),
              Text(
                'Liquid Glass — component gallery',
                style: text.titleMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.xl),

              const _Section(
                title: 'Palette',
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    _Swatch('primary', AppColors.primary),
                    _Swatch('secondary', AppColors.secondary),
                    _Swatch('tertiary', AppColors.tertiary),
                    _Swatch('success', AppColors.success),
                    _Swatch('warning', AppColors.warning),
                    _Swatch('danger', AppColors.danger),
                  ],
                ),
              ),

              _Section(
                title: 'Type ramp',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Display Small', style: text.displaySmall),
                    Text('Headline Medium', style: text.headlineMedium),
                    Text('Title Large', style: text.titleLarge),
                    Text('Body Large — the quick brown fox settles in.', style: text.bodyLarge),
                    Text(
                      'Body Medium secondary',
                      style: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),

              _Section(
                title: 'Glass surfaces',
                child: Row(
                  children: [
                    Expanded(
                      child: GlassSurface(
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Panel', style: text.titleLarge),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Frosted, translucent, refracting the glow behind it.',
                              style: text.bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: GlassSurface(
                        strong: true,
                        padding: const EdgeInsets.all(AppSpacing.lg),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Strong panel', style: text.titleLarge),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Higher fill for foreground surfaces (dialogs, nav).',
                              style: text.bodyMedium
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              _Section(
                title: 'Buttons',
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton(onPressed: () {}, child: const Text('Play')),
                    OutlinedButton(onPressed: () {}, child: const Text('More info')),
                    TextButton(onPressed: () {}, child: const Text('Details')),
                    FilledButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Resume'),
                    ),
                  ],
                ),
              ),

              const _Section(
                title: 'Status pills',
                child: Wrap(
                  spacing: AppSpacing.md,
                  runSpacing: AppSpacing.md,
                  children: [
                    _Pill('Downloaded', AppColors.success),
                    _Pill('Downloading 62%', AppColors.secondary),
                    _Pill('Not downloaded', AppColors.textTertiary),
                    _Pill('Keep', AppColors.tertiary),
                  ],
                ),
              ),

              _Section(
                title: 'Focus (remote / D-pad)',
                child: Row(
                  children: List.generate(
                    4,
                    (i) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.lg),
                      child: _FocusableGlassTile(label: 'Tile ${i + 1}'),
                    ),
                  ),
                ),
              ),

              const _Section(
                title: 'Input',
                child: SizedBox(
                  width: 420,
                  child: TextField(
                    decoration: InputDecoration(hintText: 'Search your library…'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.5,
                ),
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name, this.color);
  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 120,
          height: 72,
          decoration: BoxDecoration(color: color, borderRadius: AppRadii.rMd),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(name, style: Theme.of(context).textTheme.labelMedium),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.glassFill,
        borderRadius: AppRadii.rPill,
        border: Border.all(color: AppColors.glassStroke),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Demonstrates the focus ring every D-pad-reachable tile should use.
class _FocusableGlassTile extends StatefulWidget {
  const _FocusableGlassTile({required this.label});
  final String label;

  @override
  State<_FocusableGlassTile> createState() => _FocusableGlassTileState();
}

class _FocusableGlassTileState extends State<_FocusableGlassTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
      onShowFocusHighlight: (v) => setState(() => _focused = v),
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => null),
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: 150,
        height: 96,
        decoration: BoxDecoration(
          borderRadius: AppRadii.rLg,
          border: Border.all(
            color: _focused ? AppColors.focus : AppColors.glassStroke,
            width: _focused ? 2 : 1,
          ),
          color: AppColors.glassFill,
          boxShadow: _focused
              ? const [BoxShadow(color: AppColors.focusGlow, blurRadius: 24, spreadRadius: 1)]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(widget.label, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
