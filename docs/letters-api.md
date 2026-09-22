# HR Letters — Mobile API Requirements

**Base URL:** `https://hrms.mecpl.in/api`
**Auth:** Bearer Token (Sanctum) — `Authorization: Bearer {token}`

Backing the new **My Documents › Letters** section in the Flutter app
(`lib/screens/documents/my_documents_screen.dart`). The app is already wired
against this contract — it calls `ApiService.fetchLetterPdfBytes()` and
degrades gracefully until the routes exist.

---

## Endpoint

```
GET /api/letters/{type}?category={category}
```

| Segment | Values |
|---------|--------|
| `{type}` | `warning`, `confirmation`, `extension`, `experience`, `promotion`, `appointment` |
| `{category}` | `staff`, `apprentice`, `consultant` |

`{type}` is the letter template. `{category}` is the employment category the
letter is issued under — HR keeps a separate template per category, so the same
type resolves to a different document depending on this value.

`/letters/appointment` and `/letters/confirmation` already exist (used by the
older Profile › Documents screen, which sends no `category`). Those two must
keep working **with and without** the query parameter; when it is absent, fall
back to the employee's own category on record.

**Headers sent by the app:**
```
Authorization: Bearer {token}
Accept: application/pdf
X-API-Key: {api key}
X-Requested-With: XMLHttpRequest
```

---

## Responses

### 200 — the letter exists

Raw PDF bytes, `Content-Type: application/pdf`.

The app validates the `%PDF` magic bytes before opening the file. **A JSON
error envelope returned with a 200 status is treated as "no letter on file"** —
please use real status codes rather than `200 {"status": false}`.

### 404 — nothing on file

The normal case: most employees have never been issued a warning or promotion
letter. The app shows a plain neutral message ("No Warning Letter on file for
Staff. Please contact HR.") rather than an error.

```json
{
    "status": false,
    "message": "No warning letter found for this employee"
}
```

### 401 — token expired

Handled by the app's global `_checkAuth` (forces re-login).

### 422 — unknown type or category

Treated as a generic failure. Prefer 404 for "valid type, no document".

---

## Notes for the backend

1. **Scope to the authenticated employee.** The route takes no employee id —
   the letter must be resolved from the Bearer token, never from a request
   parameter.
2. **Latest version wins.** If several letters of the same type exist for an
   employee (e.g. two warning letters), return the most recent. A version list
   is not needed on the app side yet.
3. **Category mismatch.** If the employee's category on record does not match
   the requested one, return 404 rather than the other category's letter — the
   selector in the app is a filter, not an override.
4. **Filenames.** The app names the cached file itself
   (`{type}_letter_{category}.pdf`), so `Content-Disposition` is not required.
5. **Timeout.** The app allows 60 s per letter.
