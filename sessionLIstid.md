# Session Log - 2025-10-27

## Summary
Implemented FCM notifications for Android:
- Added POST_NOTIFICATIONS permission
- Foreground local notifications with channels (orders, deals/offers)
- Topic subscription (all_users) 
- Added broadcast-push-notification function for deals/offers/new menu items
- Wired rider order status changes to send pushes to customers
- Added push sender service
- Updated send-push-notification function
- Building profile APK
