<script setup>
import { computed, ref } from 'vue';
import BaseBubble from 'next/message/bubbles/Base.vue';
import FormattedContent from './FormattedContent.vue';
import LinkPreviewCard from './LinkPreviewCard.vue';
import AttachmentChips from 'next/message/chips/AttachmentChips.vue';
import TranslationToggle from 'dashboard/components-next/message/TranslationToggle.vue';
import { MESSAGE_TYPES } from '../../constants';
import { useMessageContext } from '../../provider.js';
import { useTranslations } from 'dashboard/composables/useTranslations';

const { content, attachments, contentAttributes, messageType } =
  useMessageContext();

const { hasTranslations, translationContent } =
  useTranslations(contentAttributes);

const renderOriginal = ref(false);
const referralImageError = ref(false);

const referralImageUrl = computed(() => {
  if (messageType.value !== MESSAGE_TYPES.INCOMING) return '';

  const referral = contentAttributes.value?.referral;
  if (!referral) return '';

  const imageUrl =
    referral.thumbnailUrl ||
    referral.thumbnail_url ||
    (typeof referral.imageUrl === 'string' && referral.imageUrl) ||
    (typeof referral.image_url === 'string' && referral.image_url);
  if (!imageUrl) return '';

  try {
    const url = new URL(imageUrl);
    return ['http:', 'https:'].includes(url.protocol) ? imageUrl : '';
  } catch {
    return '';
  }
});

const renderContent = computed(() => {
  let renderedContent;

  if (renderOriginal.value) {
    renderedContent = content.value;
  } else if (hasTranslations.value) {
    renderedContent = translationContent.value;
  } else {
    renderedContent = content.value;
  }

  if (!renderedContent || !referralImageUrl.value) return renderedContent;

  return renderedContent
    .split('\n')
    .filter(line => line.trim() !== referralImageUrl.value)
    .join('\n')
    .trimEnd();
});

const isTemplate = computed(() => {
  return messageType.value === MESSAGE_TYPES.TEMPLATE;
});

const linkPreview = computed(() => {
  return (
    contentAttributes.value?.linkPreview ||
    contentAttributes.value?.link_preview ||
    null
  );
});

const isEmpty = computed(() => {
  return !content.value && !attachments.value?.length;
});

const isDeletedContentPreserved = computed(() => {
  return (
    contentAttributes.value?.deletedContentPreserved ||
    contentAttributes.value?.deleted_content_preserved
  );
});

const handleSeeOriginal = () => {
  renderOriginal.value = !renderOriginal.value;
};
</script>

<template>
  <BaseBubble class="px-4 py-3" data-bubble-name="text">
    <div class="gap-3 flex flex-col">
      <span
        v-if="isDeletedContentPreserved"
        class="text-xs font-medium text-n-slate-11"
      >
        {{ $t('GENERAL_SETTINGS.FORM.DELETED_MESSAGE_CONTENT.NOTICE') }}
      </span>
      <span v-if="isEmpty" class="text-n-slate-11">
        {{ $t('CONVERSATION.NO_CONTENT') }}
      </span>
      <FormattedContent v-if="renderContent" :content="renderContent" />
      <img
        v-if="referralImageUrl && !referralImageError"
        data-testid="referral-image"
        class="skip-context-menu w-full max-h-80 rounded-lg object-contain"
        :src="referralImageUrl"
        alt=""
        loading="lazy"
        referrerpolicy="no-referrer"
        @error="referralImageError = true"
      />
      <LinkPreviewCard v-if="linkPreview" :preview="linkPreview" />
      <TranslationToggle
        v-if="hasTranslations"
        class="-mt-3"
        :showing-original="renderOriginal"
        @toggle="handleSeeOriginal"
      />
      <AttachmentChips :attachments="attachments" class="gap-2" />
      <template v-if="isTemplate">
        <div
          v-if="contentAttributes.submittedEmail"
          class="px-2 py-1 rounded-lg bg-n-alpha-3"
        >
          {{ contentAttributes.submittedEmail }}
        </div>
      </template>
    </div>
  </BaseBubble>
</template>

<style>
p:last-child {
  margin-bottom: 0;
}
</style>
