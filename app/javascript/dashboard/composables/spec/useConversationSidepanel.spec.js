import { useConversationSidepanel } from '../useConversationSidepanel';

describe('useConversationSidepanel', () => {
  const {
    isContactSidebarOpen,
    openContactSidebar,
    closeContactSidebar,
    toggleContactSidebar,
  } = useConversationSidepanel();

  beforeEach(() => {
    closeContactSidebar();
  });

  it('is closed by default', () => {
    expect(isContactSidebarOpen.value).toBe(false);
  });

  it('opens only after an explicit action', () => {
    openContactSidebar();

    expect(isContactSidebarOpen.value).toBe(true);
  });

  it('closes and resets the panel state', () => {
    openContactSidebar();
    closeContactSidebar();

    expect(isContactSidebarOpen.value).toBe(false);
  });

  it('supports the existing keyboard toggle', () => {
    toggleContactSidebar();
    expect(isContactSidebarOpen.value).toBe(true);

    toggleContactSidebar();
    expect(isContactSidebarOpen.value).toBe(false);
  });
});
