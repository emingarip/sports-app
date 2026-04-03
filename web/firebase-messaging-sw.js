importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js");

const firebaseConfig = {
  apiKey: "",
  projectId: "boskale-d00cc",
  messagingSenderId: "858669470500",
  appId: "",
};

const isConfigured = Object.values(firebaseConfig).every((value) => Boolean(value));

if (isConfigured) {
  firebase.initializeApp(firebaseConfig);

  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    console.log('[firebase-messaging-sw.js] Received background message ', payload);
    const notificationTitle = payload.notification?.title || 'New Sports Alert';
    const notificationOptions = {
      body: payload.notification?.body || '',
      icon: '/icons/Icon-192.png'
    };

    self.registration.showNotification(notificationTitle, notificationOptions);
  });
} else {
  console.warn('Firebase Messaging service worker disabled: missing web Firebase config.');
}
