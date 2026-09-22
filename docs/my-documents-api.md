# My Documents - Mobile API Documentation

**Base URL:** `https://hrms.mecpl.in/api`  
**Auth:** Bearer Token (Sanctum) — `Authorization: Bearer {token}`  
**Content-Type:** `application/json`

---

## Endpoints Overview

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/my-documents` | Get all document statuses (Form 16 + Health Card) |
| GET | `/api/form16/download/{id}` | Download Form 16 PDF |
| GET | `/api/health-card/download/{id}` | Download Health Card PDF |

All endpoints require `Authorization: Bearer {token}` header.

---

## 1. Get My Documents

Returns the complete document status for the authenticated employee for the current financial year. Includes Form 16 (Traces + MECPL) and Medical Health Card.

**Endpoint:** `GET /api/my-documents`

**Headers:**
```
Authorization: Bearer {token}
```

**Response (200 - Success):**
```json
{
    "status": true,
    "message": "Documents retrieved",
    "data": {
        "financial_year": "26-27",
        "form16": {
            "traces": {
                "part_a": {
                    "id": 42,
                    "available": true
                },
                "part_b": {
                    "id": 43,
                    "available": true
                }
            },
            "mecpl": {
                "count": 3,
                "available": true,
                "files": [
                    {
                        "id": 101,
                        "filename": "AAOPW6536B.pdf",
                        "version": 1
                    },
                    {
                        "id": 102,
                        "filename": "AAOPW6536B (2).pdf",
                        "version": 2
                    },
                    {
                        "id": 103,
                        "filename": "AAOPW6536B (3).pdf",
                        "version": 3
                    }
                ]
            }
        },
        "health_card": {
            "id": 55,
            "available": true
        }
    }
}
```

**Response when nothing is available:**
```json
{
    "status": true,
    "message": "Documents retrieved",
    "data": {
        "financial_year": "26-27",
        "form16": {
            "traces": {
                "part_a": { "id": null, "available": false },
                "part_b": { "id": null, "available": false }
            },
            "mecpl": {
                "count": 0,
                "available": false,
                "files": []
            }
        },
        "health_card": {
            "id": null,
            "available": false
        }
    }
}
```

**Response (404 - No FY):**
```json
{
    "status": false,
    "message": "No current financial year configured"
}
```

### Field Reference

| Path | Type | Description |
|------|------|-------------|
| `data.financial_year` | string | Current FY (e.g., "26-27") |
| `data.form16.traces.part_a.id` | int/null | Upload ID for Traces Part A |
| `data.form16.traces.part_a.available` | bool | Whether Part A PDF exists |
| `data.form16.traces.part_b.id` | int/null | Upload ID for Traces Part B |
| `data.form16.traces.part_b.available` | bool | Whether Part B PDF exists |
| `data.form16.mecpl.count` | int | Number of MECPL Part B files |
| `data.form16.mecpl.available` | bool | Whether any MECPL files exist |
| `data.form16.mecpl.files` | array | List of MECPL PDF files |
| `data.form16.mecpl.files[].id` | int | Upload ID (use for download) |
| `data.form16.mecpl.files[].filename` | string | Original filename |
| `data.form16.mecpl.files[].version` | int | Version number |
| `data.health_card.id` | int/null | Upload ID for Health Card |
| `data.health_card.available` | bool | Whether Health Card exists |

---

## 2. Download Form 16 PDF

Downloads a Form 16 PDF file. Use the `id` from the my-documents response (`traces.part_a.id`, `traces.part_b.id`, or `mecpl.files[].id`).

**Endpoint:** `GET /api/form16/download/{id}`

**Headers:**
```
Authorization: Bearer {token}
```

**Success Response (200):**
- **Content-Type:** `application/pdf`
- **Body:** Raw PDF binary data

**Error Responses:**

| Status | Body | When |
|--------|------|------|
| 404 | `{"status": false, "message": "Form 16 not found"}` | Invalid ID |
| 403 | `{"status": false, "message": "Unauthorized"}` | PDF belongs to another employee |
| 404 | `{"status": false, "message": "File not found on server"}` | File missing on disk |

---

## 3. Download Health Card PDF

Downloads the Medical Health Card PDF. Use the `id` from `data.health_card.id`.

**Endpoint:** `GET /api/health-card/download/{id}`

**Headers:**
```
Authorization: Bearer {token}
```

**Success Response (200):**
- **Content-Type:** `application/pdf`
- **Body:** Raw PDF binary data

**Error Responses:**

| Status | Body | When |
|--------|------|------|
| 404 | `{"status": false, "message": "Health card not found"}` | Invalid ID |
| 403 | `{"status": false, "message": "Unauthorized"}` | PDF belongs to another employee |
| 404 | `{"status": false, "message": "File not found on server"}` | File missing on disk |

---

## Complete Flutter Integration

### Service Class

```dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MyDocumentsService {
  final String baseUrl = 'https://hrms.mecpl.in';
  final String token;

  MyDocumentsService({required this.token});

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Accept': 'application/json',
  };

  /// Get all document statuses
  Future<Map<String, dynamic>> getDocuments() async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/my-documents'),
      headers: _headers,
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw Exception('Session expired. Please login again.');
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Failed to load documents');
    }
  }

  /// Download a Form 16 PDF by its upload ID
  Future<File> downloadForm16(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/form16/download/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200 &&
        response.headers['content-type']?.contains('pdf') == true) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/form16_$id.pdf');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Download failed');
    }
  }

  /// Download a Health Card PDF by its upload ID
  Future<File> downloadHealthCard(int id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/api/health-card/download/$id'),
      headers: {'Authorization': 'Bearer $token'},
    );

    if (response.statusCode == 200 &&
        response.headers['content-type']?.contains('pdf') == true) {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/health_card_$id.pdf');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      final error = jsonDecode(response.body);
      throw Exception(error['message'] ?? 'Download failed');
    }
  }
}
```

### Usage Example

```dart
final service = MyDocumentsService(token: userToken);

// 1. Load all documents
final result = await service.getDocuments();
final data = result['data'];

// 2. Check Form 16 - Traces
final tracesA = data['form16']['traces']['part_a'];
final tracesB = data['form16']['traces']['part_b'];
if (tracesA['available']) {
  // Show "View Part A" button
  // On tap: final file = await service.downloadForm16(tracesA['id']);
}

// 3. Check Form 16 - MECPL (multiple files)
final mecpl = data['form16']['mecpl'];
if (mecpl['available']) {
  // Show list of files
  for (final f in mecpl['files']) {
    print('${f['filename']} - ID: ${f['id']}');
    // On tap: final file = await service.downloadForm16(f['id']);
  }
}

// 4. Check Health Card
final hc = data['health_card'];
if (hc['available']) {
  // Show "View Health Card" button
  // On tap: final file = await service.downloadHealthCard(hc['id']);
}
```

### Share Example

```dart
import 'package:share_plus/share_plus.dart';

Future<void> shareDocument(File file, String title) async {
  await Share.shareXFiles(
    [XFile(file.path)],
    text: title,
  );
}
```

---

## App Screen Flow

```
My Documents Screen (call GET /api/my-documents)
    |
    ├── Form 16 Card
    │     ├── TRACES section
    │     │     ├── Part A → View/Download (GET /api/form16/download/{id})
    │     │     └── Part B → View/Download (GET /api/form16/download/{id})
    │     │
    │     └── MECPL section (multiple files)
    │           ├── File 1 → View/Download (GET /api/form16/download/{id})
    │           ├── File 2 → View/Download (GET /api/form16/download/{id})
    │           └── File N → View/Download (GET /api/form16/download/{id})
    │
    └── Medical Health Card
          └── View/Download (GET /api/health-card/download/{id})
```

**UI Logic:**
1. Call `GET /api/my-documents` on screen load
2. Show cards for Form 16 and Health Card
3. Each card shows "Available" or "Missing" badge
4. On tap Form 16 card → expand to show Traces (Part A/B) + MECPL (file list)
5. On tap Health Card → View/Download if available, "Contact HR" if not
6. All downloads use the respective download endpoints with the `id` from the status response

---

## Error Handling

| HTTP Status | Meaning | App Action |
|-------------|---------|------------|
| 200 | Success | Process response |
| 401 | Token expired/invalid | Redirect to login |
| 403 | Not authorized | Show error |
| 404 | Not found / No FY | Show "Not Available" |
| 500 | Server error | Show "Try again later" |

---

## Notes

- **Single API call**: `GET /api/my-documents` returns everything in one request — no need for separate calls
- **Form 16 Traces**: Part A + Part B are single files (latest version only)
- **Form 16 MECPL**: Multiple Part B files per employee — all returned as a list
- **Health Card**: Single file per FY
- **Download endpoints** verify ownership — employees can only access their own documents
- PDFs are typically 55-60 KB each
- Token does not expire; revoked via `POST /api/logout`
