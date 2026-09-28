import {
  currentLocation,
  loadLocationMap,
  locationMessagePayload,
} from '../locationSharing';
import { createPendingMessage } from '../commons';
import { Capacitor } from '@capacitor/core';
import { Geolocation } from '@capacitor/geolocation';

vi.mock('@capacitor/core', () => ({
  Capacitor: {
    isNativePlatform: vi.fn(() => false),
    getPlatform: vi.fn(() => 'android'),
  },
}));
vi.mock('@capacitor/geolocation', () => ({
  Geolocation: {
    getCurrentPosition: vi.fn(),
    checkPermissions: vi.fn(),
    requestPermissions: vi.fn(),
  },
}));

describe('location sharing', () => {
  it('requests iOS permission before reading a position', async () => {
    Capacitor.isNativePlatform.mockReturnValueOnce(true);
    Capacitor.getPlatform.mockReturnValueOnce('ios');
    Geolocation.checkPermissions.mockResolvedValueOnce({ location: 'prompt' });
    Geolocation.requestPermissions.mockResolvedValueOnce({
      location: 'granted',
    });
    Geolocation.getCurrentPosition.mockResolvedValueOnce({
      coords: { latitude: 1, longitude: 2 },
    });
    await expect(currentLocation()).resolves.toEqual({
      coords: { latitude: 1, longitude: 2 },
    });
    expect(Geolocation.requestPermissions).toHaveBeenCalledWith({
      permissions: ['location'],
    });
    expect(
      Geolocation.requestPermissions.mock.invocationCallOrder.at(-1)
    ).toBeLessThan(
      Geolocation.getCurrentPosition.mock.invocationCallOrder.at(-1)
    );
  });
  it('does not read GPS or repeatedly prompt when iOS permission was denied', async () => {
    Capacitor.isNativePlatform.mockReturnValueOnce(true);
    Capacitor.getPlatform.mockReturnValueOnce('ios');
    Geolocation.checkPermissions.mockResolvedValueOnce({ location: 'denied' });
    Geolocation.getCurrentPosition.mockClear();
    Geolocation.requestPermissions.mockClear();
    await expect(currentLocation()).rejects.toThrow(
      'LOCATION_PERMISSION_DENIED'
    );
    expect(Geolocation.getCurrentPosition).not.toHaveBeenCalled();
    expect(Geolocation.requestPermissions).not.toHaveBeenCalled();
  });
  afterEach(() => {
    vi.restoreAllMocks();
    vi.unstubAllGlobals();
  });
  it('does not load Google without a configured key', async () => {
    await expect(loadLocationMap('')).rejects.toThrow('MAP_NOT_CONFIGURED');
    expect(
      document.querySelector('script[src*="maps.googleapis.com"]')
    ).toBeNull();
  });
  it('reuses a loaded maps library', async () => {
    window.google = { maps: { importLibrary: vi.fn() } };
    await expect(loadLocationMap('test')).resolves.toBe(window.google.maps);
    delete window.google;
  });
  it('requests a fresh position only when called', async () => {
    const getCurrentPosition = vi.fn(resolve =>
      resolve({ coords: { latitude: 0, longitude: 0 } })
    );
    vi.stubGlobal('navigator', { geolocation: { getCurrentPosition } });
    expect(getCurrentPosition).not.toHaveBeenCalled();
    await expect(currentLocation()).resolves.toEqual({
      coords: { latitude: 0, longitude: 0 },
    });
    expect(getCurrentPosition).toHaveBeenCalledWith(
      expect.any(Function),
      expect.any(Function),
      { enableHighAccuracy: true, timeout: 15000, maximumAge: 0 }
    );
  });
  it('propagates denied permission', async () => {
    vi.stubGlobal('navigator', {
      geolocation: { getCurrentPosition: (_, reject) => reject({ code: 1 }) },
    });
    await expect(currentLocation()).rejects.toEqual({ code: 1 });
  });
  it('uses native GPS on Android/iOS', async () => {
    Capacitor.isNativePlatform.mockReturnValueOnce(true);
    Geolocation.getCurrentPosition.mockResolvedValueOnce({
      coords: { latitude: 1, longitude: 2 },
    });
    await expect(currentLocation()).resolves.toEqual({
      coords: { latitude: 1, longitude: 2 },
    });
  });
  it('creates a location bubble, including zero coordinates, without file upload', () => {
    const location = {
      latitude: 0,
      longitude: 0,
      name: 'Place',
      address: 'Address',
    };
    const message = createPendingMessage(locationMessagePayload(42, location));
    expect(message.contentAttributes.location).toEqual(location);
    expect(message.attachments).toEqual([
      expect.objectContaining({
        file_type: 'location',
        coordinates_lat: 0,
        coordinates_long: 0,
      }),
    ]);
    expect(message.file).toBeUndefined();
    expect(message.private).toBe(false);
    expect(message.conversation_id).toBe(42);
  });
});
