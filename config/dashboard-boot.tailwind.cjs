// Independent, tiny stylesheet: the splash cannot depend on the Vite bundle.
// Regenerate with: pnpm exec tailwindcss -c config/dashboard-boot.tailwind.cjs -o public/dashboard-boot-v1.css --minify
module.exports = {
  content: ['./app/views/layouts/_dashboard_boot.html.erb'],
  darkMode: 'class',
  corePlugins: { preflight: false },
};
