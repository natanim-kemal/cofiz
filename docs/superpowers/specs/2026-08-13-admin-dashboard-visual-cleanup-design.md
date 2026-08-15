# App-Wide Visual Cleanup Design

## Goal

Refresh the Cofiz Flutter interface with a quieter, cleaner visual system while preserving all existing behavior, navigation, role restrictions, localization, and data flows.

## Scope

The changes apply across the entire Flutter app, with the admin dashboard as the first validation surface.

### Typography

- Replace the current Outfit text theme with DM Sans using the existing `google_fonts` dependency.
- Apply DM Sans to both light and dark `ThemeData` text themes.
- Preserve existing text hierarchy, weights, and screen-specific overrides unless they are required for compilation or visual consistency.

### Background

- Remove the decorative dot pattern rendered by `BackgroundPattern`.
- Preserve the widget API and any child composition so screens that use it continue to lay out and render correctly.
- Preserve the existing light and dark scaffold/background colors.

### Cards and Borders

- Remove decorative orange borders created with `AppColors.primary` around cards and summary panels.
- Preserve card surface colors, corner radii, shadows, spacing, and functional form/input borders.
- Preserve borders that communicate state or interaction, such as chips, input validation, and notification/status indicators.

### Icons

- Remove decorative translucent or opaque containers placed behind ordinary icons across screens and reusable widgets.
- Increase ordinary icon sizes modestly where the existing wrapper removal would make them visually undersized, generally from 20 to 24 and from 24 to 28.
- Preserve `IconButton` touch targets and padding even when its visual background is removed.
- Preserve avatars, badges, status indicators, and other elements whose container conveys meaning rather than decoration.

## Implementation Boundaries

- Prefer shared theme and widget changes over duplicated screen-specific overrides.
- Do not change business logic, provider behavior, Firebase access, navigation, or localization content.
- Do not remove the orange accent color; it remains available for primary actions and semantic emphasis.

## Verification

- Run `flutter analyze` and confirm there are no analyzer errors.
- Run `flutter build apk --debug`.
- Run `flutter run` against the connected Android device when available.
- Manually inspect the admin dashboard and representative screens for the absence of the dot background, decorative card borders, and ordinary icon containers.

## Acceptance Criteria

- The app uses DM Sans throughout standard Material text styles.
- No dot pattern is painted by `BackgroundPattern`.
- Dashboard and shared cards no longer show decorative warm-orange outlines.
- Ordinary icons render directly without decorative background containers and remain easy to tap.
- Functional states and interaction affordances remain visible.
- Existing app behavior remains unchanged.
