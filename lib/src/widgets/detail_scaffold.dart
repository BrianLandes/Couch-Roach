import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'app_back_button.dart';

/// Height reserved at the top for the pinned detail header. The scroll body is
/// inset by this much; the header floats over it.
const double _kDetailHeaderHeight = 64;

/// Standard layout for a detail page (show / movie / library title): an
/// [AmbientBackground] with a **pinned** top bar over a scrolling body. The back
/// button stays put at the top at any scroll depth (see docs/STYLE.md — every
/// screen but the landing page has a reachable back button), and the [title]
/// fades into the bar once the hero has scrolled up under it, so it isn't shown
/// twice while the hero's own large title is still on screen.
class DetailScaffold extends StatefulWidget {
  const DetailScaffold({
    super.key,
    required this.title,
    required this.children,
  });

  /// Page title — the show/movie name. Revealed in the pinned bar on scroll.
  final String title;

  /// The scrolling body, below the pinned header. Horizontal screen padding is
  /// applied here; children are laid out in a [ListView].
  final List<Widget> children;

  @override
  State<DetailScaffold> createState() => _DetailScaffoldState();
}

class _DetailScaffoldState extends State<DetailScaffold> {
  final _controller = ScrollController();

  // Reveal the pinned title once the hero's own title has scrolled up roughly
  // under the bar. Not pixel-exact — a small scroll before it appears reads as
  // intentional rather than flickering on the first pixel.
  static const _revealAfter = 56.0;
  bool _showTitle = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final show = _controller.hasClients && _controller.offset > _revealAfter;
    if (show != _showTitle) setState(() => _showTitle = show);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AmbientBackground(
        child: SafeArea(
          child: Stack(
            children: [
              ListView(
                controller: _controller,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  _kDetailHeaderHeight + AppSpacing.sm,
                  AppSpacing.screenPadding,
                  AppSpacing.screenPadding,
                ),
                children: widget.children,
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: _DetailHeader(
                  title: widget.title,
                  showTitle: _showTitle,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The pinned bar: back button always, title cross-fading in with a frosted
/// backdrop once [showTitle] is set (so scrolling content reads cleanly under
/// it instead of colliding with the button and title).
class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.title, required this.showTitle});

  final String title;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      height: _kDetailHeaderHeight,
      decoration: BoxDecoration(
        color: showTitle ? AppColors.bg : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: showTitle ? AppColors.glassStroke : Colors.transparent,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      child: Row(
        children: [
          const AppBackButton(),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              opacity: showTitle ? 1 : 0,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.titleLarge,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
