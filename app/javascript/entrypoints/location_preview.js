import '../dashboard/assets/css/locationMap.css';

// Keep Google's referrer on the installation HTTPS origin, including Capacitor.
document.documentElement.className = 'h-full w-full';
document.body.className = 'h-full w-full m-0 overflow-hidden';
const container = document.getElementById('location-preview');
container.className = 'h-full w-full';
const params = new URLSearchParams(window.location.search);
const lat = Number(params.get('lat'));
const lng = Number(params.get('lng'));
const fail = () =>
  window.parent.postMessage(
    { source: 'viper-location-preview', type: 'error' },
    '*'
  );
if (
  !container.dataset.apiKey ||
  !params.has('lat') ||
  !params.has('lng') ||
  !Number.isFinite(lat) ||
  !Number.isFinite(lng) ||
  Math.abs(lat) > 90 ||
  Math.abs(lng) > 180
) {
  fail();
} else {
  const image = new Image();
  image.alt = 'Google Maps';
  image.className = 'block h-full w-full object-contain';
  image.onerror = fail;
  image.src = `https://maps.googleapis.com/maps/api/staticmap?${new URLSearchParams(
    {
      center: `${lat},${lng}`,
      zoom: '17',
      size: '320x160',
      scale: '2',
      maptype: 'roadmap',
      markers: `color:red|${lat},${lng}`,
      language: 'pt-BR',
      key: container.dataset.apiKey,
    }
  )}`;
  container.append(image);
}
