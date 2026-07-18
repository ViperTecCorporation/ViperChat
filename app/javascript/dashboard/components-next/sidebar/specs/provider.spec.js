import { useSidebarResize } from '../provider';

const mocks = vi.hoisted(() => ({
  uiSettings: { value: {} },
  updateUISettings: vi.fn(),
}));

vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => mocks,
}));

describe('useSidebarResize', () => {
  beforeEach(() => {
    mocks.uiSettings.value = {};
    mocks.updateUISettings.mockClear();
  });

  it('starts collapsed when no width preference exists', () => {
    const { sidebarWidth, isCollapsed } = useSidebarResize();

    expect(sidebarWidth.value).toBe(56);
    expect(isCollapsed.value).toBe(true);
  });

  it('keeps an explicitly saved width preference', () => {
    mocks.uiSettings.value = { sidebar_width: 240 };

    const { sidebarWidth, isCollapsed } = useSidebarResize();

    expect(sidebarWidth.value).toBe(240);
    expect(isCollapsed.value).toBe(false);
  });

  it('expands to the standard desktop width', () => {
    const { sidebarWidth, snapToExpanded } = useSidebarResize();

    snapToExpanded();

    expect(sidebarWidth.value).toBe(200);
    expect(mocks.updateUISettings).toHaveBeenCalledWith({
      sidebar_width: 200,
    });
  });

  it('persists the collapsed width and restores it on the next load', () => {
    mocks.uiSettings.value = { sidebar_width: 240 };
    const { snapToCollapsed } = useSidebarResize();

    snapToCollapsed();

    expect(mocks.updateUISettings).toHaveBeenCalledWith({ sidebar_width: 56 });

    mocks.uiSettings.value = { sidebar_width: 56 };
    const restoredSidebar = useSidebarResize();

    expect(restoredSidebar.sidebarWidth.value).toBe(56);
    expect(restoredSidebar.isCollapsed.value).toBe(true);
  });
});
