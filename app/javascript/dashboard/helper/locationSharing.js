import { Capacitor } from '@capacitor/core';
import { Geolocation } from '@capacitor/geolocation';

let mapsPromise;

export const loadLocationMap = apiKey => {
  if (!apiKey) return Promise.reject(new Error('MAP_NOT_CONFIGURED'));
  if (window.google?.maps?.importLibrary)
    return Promise.resolve(window.google.maps);
  if (mapsPromise) return mapsPromise;

  mapsPromise = new Promise((resolve, reject) => {
    const script = document.createElement('script');
    let timer;
    const fail = () => {
      clearTimeout(timer);
      script.remove();
      mapsPromise = null;
      reject(new Error('MAP_LOAD_FAILED'));
    };
    timer = setTimeout(fail, 20000);
    window.viperLocationMapLoaded = () => {
      clearTimeout(timer);
      resolve(window.google.maps);
    };
    script.src = `https://maps.googleapis.com/maps/api/js?${new URLSearchParams(
      {
        key: apiKey,
        v: 'quarterly',
        loading: 'async',
        callback: 'viperLocationMapLoaded',
      }
    )}`;
    script.async = true;
    script.onerror = fail;
    document.head.appendChild(script);
  });
  return mapsPromise;
};

export const currentLocation = async () => {
  if (Capacitor.isNativePlatform()) {
    if (Capacitor.getPlatform() === 'ios') {
      let permission = await Geolocation.checkPermissions();
      if (
        permission.location === 'prompt' ||
        permission.location === 'prompt-with-rationale'
      ) {
        permission = await Geolocation.requestPermissions({
          permissions: ['location'],
        });
      }
      if (permission.location !== 'granted') {
        throw new Error('LOCATION_PERMISSION_DENIED');
      }
    }
    return Geolocation.getCurrentPosition({
      enableHighAccuracy: true,
      timeout: 15000,
      maximumAge: 0,
    });
  }
  return new Promise((resolve, reject) => {
    if (!navigator.geolocation) {
      reject(new Error('GEOLOCATION_UNAVAILABLE'));
      return;
    }
    navigator.geolocation.getCurrentPosition(resolve, reject, {
      enableHighAccuracy: true,
      timeout: 15000,
      maximumAge: 0,
    });
  });
};

export const locationMessagePayload = (conversationId, location) => ({
  conversationId,
  message: [location.name, location.address].filter(Boolean).join(' — '),
  private: false,
  contentType: 'text',
  contentAttributes: { location },
});
