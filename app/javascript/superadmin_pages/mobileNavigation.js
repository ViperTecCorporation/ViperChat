export const setupMobileNavigation = () => {
  document.querySelectorAll('main table').forEach(table => {
    if (table.parentElement.dataset.scrollTable) return;
    const wrapper = document.createElement('div');
    wrapper.className = 'w-full max-w-full overflow-x-auto';
    wrapper.dataset.scrollTable = 'true';
    table.before(wrapper);
    wrapper.append(table);
  });
  const button = document.getElementById('super-admin-menu-toggle');
  const navigation = document.getElementById('super-admin-navigation');
  if (!button || !navigation) return;

  const close = () => {
    navigation.classList.add('hidden');
    button.setAttribute('aria-expanded', 'false');
  };
  button.addEventListener('click', () => {
    const hidden = navigation.classList.toggle('hidden');
    button.setAttribute('aria-expanded', String(!hidden));
  });
  navigation.addEventListener('click', event => {
    if (event.target.closest('a')) close();
  });
  document.addEventListener('keydown', event => {
    if (
      event.key === 'Escape' &&
      button.getAttribute('aria-expanded') === 'true'
    ) {
      close();
      button.focus();
    }
  });
  window.matchMedia('(min-width: 768px)').addEventListener('change', close);
};
