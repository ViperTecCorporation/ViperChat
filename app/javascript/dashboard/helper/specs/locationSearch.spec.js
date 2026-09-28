import { searchLocationPlaces } from '../locationSearch';

describe('searchLocationPlaces', () => {
  const searchByText = vi.fn();
  const maps = { importLibrary: vi.fn() };
  beforeEach(() => {
    maps.importLibrary.mockResolvedValue({ Place: { searchByText } });
  });
  it('searches businesses and addresses with a bias, not a geographic restriction', async () => {
    const bounds = { north: -11, south: -12, east: -54, west: -55 };
    searchByText.mockResolvedValue({
      places: [
        {
          id: 'company',
          displayName: 'Vipertec',
          formattedAddress: 'Sinop, MT',
          location: { lat: () => -11.5, lng: () => -54.8 },
        },
      ],
    });
    expect(await searchLocationPlaces(maps, ' Vipertec ', bounds)).toEqual([
      {
        id: 'company',
        name: 'Vipertec',
        address: 'Sinop, MT',
        latitude: -11.5,
        longitude: -54.8,
      },
    ]);
    expect(maps.importLibrary).toHaveBeenCalledWith('places');
    expect(searchByText).toHaveBeenCalledWith({
      textQuery: 'Vipertec',
      fields: ['id', 'displayName', 'formattedAddress', 'location'],
      locationBias: bounds,
      maxResultCount: 8,
    });
  });
  it('returns no results without treating it as an API error', async () => {
    searchByText.mockResolvedValue({ places: [] });
    expect(await searchLocationPlaces(maps, 'missing')).toEqual([]);
    expect(searchByText.mock.calls[0][0]).not.toHaveProperty('locationBias');
  });
  it('omits results without coordinates and accepts zero coordinates', async () => {
    searchByText.mockResolvedValue({
      places: [
        { id: 'missing' },
        {
          id: 'zero',
          location: { lat: () => 0, lng: () => 0 },
        },
      ],
    });
    expect(await searchLocationPlaces(maps, 'address')).toEqual([
      {
        id: 'zero',
        name: '',
        address: '',
        latitude: 0,
        longitude: 0,
      },
    ]);
  });
  it('propagates API failures without retrying or falling back silently', async () => {
    searchByText.mockRejectedValue(new Error('REQUEST_DENIED'));
    await expect(searchLocationPlaces(maps, 'Vipertec')).rejects.toThrow(
      'REQUEST_DENIED'
    );
    expect(searchByText).toHaveBeenCalledTimes(1);
  });
});
