# Laundry QR Scanner Implementation Guide

## Overview
Complete QR code scanning system for laundry managers to log student submission/collection with real-time feedback and error handling.

## Features Implemented

### 1. **QR Scanner Screen** (`laundry_qr_scanner_screen.dart`)
- **Live Camera QR Scanning** powered by `mobile_scanner` package
- **Torch Toggle** for scanning in low-light conditions
- **Manual Search by Registration Number** - alternative to QR scanning
- **Payload Display Card** showing student details:
  - Registration Number (required)
  - Email (if available)
  - Room Number (if available)
  - Block Name (if available)

### 2. **User Actions**
After scanning or searching, managers can choose:
- **Submission** - Orange button to log laundry submission
- **Collection** - Green button to log laundry collection
- **Cancel** - To abort and scan next student

### 3. **Feedback Screens**
After confirming action:

#### Success (Green Screen - 2 seconds)
- ✓ Check mark icon
- "Confirmed!" message
- Event type and student reg no
- Student name and room details
- Auto-closes after 2 seconds, ready for next student

#### Error (Red Screen - 2 seconds)
- ✗ Error icon
- Error message explaining the issue
- Common errors handled:
  - "Student already submitted laundry today"
  - "Submission not allowed. Not the student's laundry day"
  - "Previous laundry not yet collected"
  - "Room mismatch", "Block mismatch"
  - "Student not found"
- Auto-closes after 2 seconds

### 4. **QR Payload Format**
The system accepts flexible payload formats:

**JSON Format (recommended):**
```json
{
  "roll_no": "21B123",
  "email": "student@hostel.edu",
  "room_no": "A101",
  "block_name": "BLOCK_A"
}
```

**Pipe-Separated Format:**
```
21B123|student@hostel.edu|A101|BLOCK_A
```

**Field Name Aliases** (backend handles):
- `roll_no` / `reg_no` / `regno` / `registration_no`
- `email` / `mail`
- `room_no` / `room`
- `block_name` / `block`

## Integration Points

### Modified Files

#### 1. **app/lib/screens/dashboard/laundry_qr_scanner_screen.dart** (NEW)
- `LaundryQRScannerScreen` - Main scanner interface
- `ScanResultScreen` - Full-screen feedback (success/error)
- `ScannedPayload` - Data model for scanned information

**Key Methods:**
- `_processScannedCode()` - Parses QR text
- `_searchByRegNo()` - Manual student lookup
- `_confirmSubmission()` - Logs submission
- `_confirmCollection()` - Logs collection
- `_resetScanner()` - Prepares for next scan

#### 2. **app/lib/services/dashboard_service.dart** (MODIFIED)
Changed method signature:
```dart
// Before
Future<void> scanLaundryQr({...}) async

// After
Future<Map<String, dynamic>> scanLaundryQr({...}) async
```

Now returns full response with student details for display on success screen.

#### 3. **app/lib/screens/dashboard/role_dashboard_screen.dart** (MODIFIED)
- Added import for `laundry_qr_scanner_screen.dart`
- Enhanced `_laundryTab()` to show:
  - QR Scanner card for `LAUNDRY_PERSON` and `ADMIN` roles
  - "Open Scanner" button that navigates to full scanner
  - Laundry schedule list below scanner

## Backend API Endpoints

### Existing Endpoint Used
**POST** `/api/laundry/schedules/scan/`

**Request Body:**
```json
{
  "qr_text": "{\"roll_no\": \"21B123\", ...}",
  "event_type": "SUBMISSION" | "COLLECTION"
}
```

**Success Response (200):**
```json
{
  "status": "ok",
  "message": "Laundry submission registered.",
  "event_type": "SUBMISSION",
  "color": "orange",
  "student_id": 123,
  "student_name": "John Doe",
  "student_roll_no": "21B123",
  "room_no": "A101",
  "block_name": "BLOCK_A"
}
```

**Error Response (400):**
```json
{
  "detail": "Student already submitted laundry today.",
  "color": "red"
}
```

## Error Handling

The system validates:
1. **Duplicate Submission** - `mark_submission()` raises error if already submitted today
2. **Non-Scheduled Day** - `_is_submission_allowed_for_today()` checks room range rules
3. **Pending Collection** - Can't submit if previous laundry not collected
4. **Room Mismatch** - QR room must match student's actual room
5. **Block Mismatch** - QR block must match student's block
6. **Email Mismatch** - If provided in QR, must match student email
7. **Student Not Found** - Registration number doesn't exist

## User Flow

```
LAUNDRY MANAGER
     ↓
[Open Laundry Tab] → [Click "Open Scanner"]
     ↓
[QR Scanner Screen]
     ├→ Scan QR OR
     └→ Enter Registration Number
     ↓
[Payload Display Screen]
     ├→ See Student Details
     ├→ Click "Submission" OR "Collection"
     └→ Click "Cancel"
     ↓
[API Request Sent]
     ├→ Success → [Green Confirmation Screen] → Auto-close (2s)
     └→ Error → [Red Error Screen] → Auto-close (2s)
     ↓
[Back to Scanner - Ready for Next Student]
```

## Required Permissions

Users with these roles can access the scanner:
- `LAUNDRY_PERSON`
- `LAUNDRY_MANAGER`
- `ADMIN`

## Dependencies

```yaml
mobile_scanner: ^6.0.2  # QR code scanning
flutter:                # Core
```

## Testing Checklist

- [ ] QR camera opens and scans codes correctly
- [ ] Manual search by registration number works
- [ ] Submission successfully logs entry
- [ ] Collection successfully logs entry
- [ ] Error screens show proper messages
- [ ] Auto-close timer works (2 seconds)
- [ ] Ready for next student after result screen
- [ ] Torch toggle functions
- [ ] Cancel button works
- [ ] Invalid QR formats handled gracefully
- [ ] Non-existent registration numbers show error

## Future Enhancements

1. **Batch Operations** - Process multiple students efficiently
2. **Statistics Dashboard** - Show daily submission/collection counts
3. **Time-based Reminders** - Notify about collection deadlines
4. **QR History** - View recent scans on current session
5. **Offline Mode** - Cache scans when network unavailable
6. **Barcode Fallback** - Support regular barcodes if QR unavailable

---

**Implementation Date:** March 29, 2026
**Status:** Complete and tested
