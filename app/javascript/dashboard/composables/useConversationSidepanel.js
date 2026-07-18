import { readonly, ref } from 'vue';

const isContactSidebarOpen = ref(false);

export const useConversationSidepanel = () => {
  const openContactSidebar = () => {
    isContactSidebarOpen.value = true;
  };

  const closeContactSidebar = () => {
    isContactSidebarOpen.value = false;
  };

  const toggleContactSidebar = () => {
    isContactSidebarOpen.value = !isContactSidebarOpen.value;
  };

  return {
    isContactSidebarOpen: readonly(isContactSidebarOpen),
    openContactSidebar,
    closeContactSidebar,
    toggleContactSidebar,
  };
};
