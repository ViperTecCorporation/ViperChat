export const superAdminText = key =>
  JSON.parse(document.body.dataset.superAdminLabels || '{}')[key] || key;
