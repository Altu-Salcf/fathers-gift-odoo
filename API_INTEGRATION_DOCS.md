# API Integration Documentation
## SLF Mobile API

This project uses a set of custom Odoo APIs for the Father's Gift Application.

### 1. Configuration
The API connection is managed in `lib/services/api_service.dart`.
Update the `baseUrl` inside the `ApiService` class when deploying to production with the actual IP address or domain:
```dart
class ApiService {
  static const String baseUrl = 'http://10.10.131.43:8069/api/mobile';
  static const String baseNfcUrl = 'http://10.10.131.43:8069/api';
  // ...
}
```

### 2. Available Endpoints

#### Login (`POST /api/mobile/login`)
- **Action**: Authenticates the user.
- **Request Body**: `{"username": "<username>", "password": "<password>"}`
- **Response**: The backend returns a `token`, which the app stores securely in `FlutterSecureStorage` under the key `auth_token`. In `login_screen.dart`, user types credentials.

#### Balance (`POST /api/mobile/balance`)
- **Action**: Fetches the user's available balance in `FathersGiftScreen`.
- **Request Headers**: `Authorization: Bearer <token>`
- **Request Body**: `{"token": "<token>"}`
- **Response**: Extracted for displaying `balance`.

#### Transactions (`POST /api/mobile/transactions`)
- **Action**: Fetches the recent transactions in `FathersGiftScreen`.
- **Request Headers**: `Authorization: Bearer <token>`
- **Request Body**: `{"token": "<token>"}`
- **Response**: Returns a JSON representation of orders/transactions mapping to `_transactions` list payload.

#### NFC Tap (`POST /api/nfc_tap`)
- **Action**: A loose implementation is provided in `ApiService.nfcTap()`. 
- **Note**: The application acts primarily as a Host Card Emulation (HCE) providing the `studentId`/`nfcId` to the Point-of-Sale reader. The reader itself usually hits the `nfc_tap` endpoint. 

### 3. Error Handling and Null-Safety
We implemented safe null-checks `??` during JSON parsing in `fathers_gift_screen.dart` ensuring if the keys differ slightly pending final API structures, the app won't crash.

**Developer note**: Run the following to update dependencies and apply changes: `flutter run`
