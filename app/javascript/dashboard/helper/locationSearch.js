export const searchLocationPlaces = async (maps, query, bounds) => {
  const { Place } = await maps.importLibrary('places');
  const { places } = await Place.searchByText({
    textQuery: query.trim().slice(0, 512),
    fields: ['id', 'displayName', 'formattedAddress', 'location'],
    ...(bounds ? { locationBias: bounds } : {}),
    maxResultCount: 8,
  });
  return places
    .filter(place => place.location)
    .map(place => ({
      id: place.id,
      name: place.displayName || '',
      address: place.formattedAddress || '',
      latitude: place.location.lat(),
      longitude: place.location.lng(),
    }));
};
