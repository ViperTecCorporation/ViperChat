import { loadLocationMap } from '../dashboard/helper/locationSharing';
import { searchLocationPlaces } from '../dashboard/helper/locationSearch';
import '../dashboard/assets/css/locationMap.css';

const container = document.getElementById('location-map');
// This isolated HTTPS document also works inside Capacitor: Google sees the
// installation's referrer, never an unrestricted key on capacitor://localhost.
document.documentElement.className = 'h-full w-full';
document.body.className = 'h-full w-full m-0 overflow-hidden';
container.className = 'h-full w-full';

const allowedOrigins = new Set([
  window.location.origin,
  'capacitor://localhost',
  'https://localhost',
  'http://localhost',
]);
let parentOrigin;
let map;
let marker;
let sequence = 0;
const tellParent = data => {
  if (parentOrigin)
    window.parent.postMessage(
      { source: 'viper-location-map', ...data },
      parentOrigin
    );
};
const select = (position, address = '', name = '') => {
  sequence += 1;
  marker.position = position;
  map.panTo(position);
  map.setZoom(16);
  tellParent({
    type: 'point',
    point: { latitude: position.lat(), longitude: position.lng() },
    address,
    name,
  });
};

window.addEventListener('message', async event => {
  if (
    event.source !== window.parent ||
    !allowedOrigins.has(event.origin) ||
    event.data?.source !== 'viper-location-picker'
  )
    return;
  parentOrigin = event.origin;
  const data = event.data;
  if (!map) return;
  if (
    data.type === 'select' &&
    Number.isFinite(data.latitude) &&
    Number.isFinite(data.longitude)
  ) {
    select(
      new window.google.maps.LatLng(data.latitude, data.longitude),
      String(data.address || ''),
      String(data.name || '')
    );
  } else if (data.type === 'search' && typeof data.query === 'string') {
    sequence += 1;
    const request = sequence;
    try {
      const results = await searchLocationPlaces(
        window.google.maps,
        data.query,
        map.getBounds()
      );
      if (request === sequence)
        tellParent({
          type: 'results',
          results,
        });
    } catch {
      if (request === sequence)
        tellParent({ type: 'error', code: 'SEARCH_ERROR' });
    }
  }
});

const start = async () => {
  const maps = await loadLocationMap(container.dataset.apiKey);
  const [{ Map }, { AdvancedMarkerElement }] = await Promise.all([
    maps.importLibrary('maps'),
    maps.importLibrary('marker'),
  ]);
  map = new Map(container, {
    center: { lat: -14.2, lng: -51.9 },
    zoom: 4,
    mapId: 'DEMO_MAP_ID',
    streetViewControl: false,
    fullscreenControl: false,
  });
  marker = new AdvancedMarkerElement({ map, gmpDraggable: true });
  map.addListener('click', event => select(event.latLng));
  marker.addListener('dragend', event => select(event.latLng));
  window.parent.postMessage(
    { source: 'viper-location-map', type: 'ready' },
    '*'
  );
};
window.gm_authFailure = () =>
  window.parent.postMessage(
    { source: 'viper-location-map', type: 'error', code: 'MAP_ERROR' },
    '*'
  );
start().catch(() =>
  window.parent.postMessage(
    {
      source: 'viper-location-map',
      type: 'error',
      code: container.dataset.apiKey ? 'MAP_ERROR' : 'NOT_CONFIGURED',
    },
    '*'
  )
);
