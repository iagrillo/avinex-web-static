/* eslint-disable no-undef */
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

// Replace placeholders with your Firebase web app values.
firebase.initializeApp({
  apiKey: 'AIzaSyCRuHk2Y68kkY2iH26BwlQrTY49tdajcuE',
  authDomain: 'avinex-escrow.firebaseapp.com',
  projectId: 'avinex-escrow',
  storageBucket: 'avinex-escrow.appspot.com',
  messagingSenderId: '1064992962827',
  appId: '1:1064992962827:android:6eb5ea7b6dadef90c9ca0e',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || 'Avinex Escrow';
  const body = payload.notification?.body || 'You have a new update.';

  const options = {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-maskable-192.png',
    data: {
      escrowId:
        payload?.data?.escrow_id || payload?.data?.escrowId || '',
      notificationId: payload?.data?.notificationId || '',
      type: payload?.data?.type || 'info',
    },
  };

  self.registration.showNotification(title, options);
});

self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const escrowId = event.notification?.data?.escrowId || '';
  const targetUrl = escrowId
    ? `/#/core/home-wallet-overview?escrowId=${encodeURIComponent(escrowId)}`
    : '/#/notifications/buyer-center';

  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          client.navigate(targetUrl);
          return client.focus();
        }
      }
      if (clients.openWindow) {
        return clients.openWindow(targetUrl);
      }
      return undefined;
    }),
  );
});
