# Bundled forms

These PDFs back two sections of **Useful Links**. Drop the real PDF files here
using these exact filenames (lowercase, no spaces):

## Medical Health Card

Blank claim forms.

| Sub-item in app | Required filename            |
| --------------- | ---------------------------- |
| Claim Form GPA  | `claim_form_gpa.pdf`         |
| Form A and B    | `form_a_and_b.pdf`           |
| Claim Form EC   | `claim_form_ec.pdf`          |

## Form 16 → TRACES — offline fallback only

| Card in app | Fallback filename     |
| ----------- | --------------------- |
| Part A      | `form16_part_a.pdf`   |
| Part B      | `form16_part_b.pdf`   |

Unlike the claim forms above, these are **not** the primary source. The real
certificates come from the API:

- `GET /api/form16/status` decides whether each part exists at all.
- `GET /api/form16/download/{id}` returns the PDF bytes for an available part.

These bundled files are used **only** when a part is marked available but the
download fails (offline, server error). The card then labels itself "Offline
sample" so the sample is never mistaken for the real certificate.

> **Both files here are generated placeholders, not real certificates.** They
> exist so the view / share / download flow stays testable without a network.

If a file is missing, tapping its sub-item shows a "could not open" message
rather than crashing. After adding/replacing files, run `flutter pub get`
(or a hot restart / rebuild) so the new asset bytes are bundled.
