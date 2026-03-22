importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

// Initialize the Firebase app in the service worker by passing in the
// messagingSenderId.
firebase.initializeApp({
  apiKey: "AIzaSyDLTwqiaptfxY0zwj2VUUjHZ_KaVPZ5xMo",
  projectId: "boskale-d00cc",
  messagingSenderId: "858669470500",
  appId: "1:858669470500:web:abcdef1234567890" // Firebase accepts correctly formatted App IDs
});

// Retrieve an instance of Firebase Messaging so that it can handle background
// messages.
const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  // Customize notification here
  const notificationTitle = payload.notification.title || 'New Sports Alert';
  const notificationOptions = {
    body: payload.notification.body || '',
    icon: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});
