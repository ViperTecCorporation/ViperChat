<script setup>
import { computed, ref } from 'vue';
import FileUpload from 'vue-upload-component';

import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import AudioRecorder from 'dashboard/components/widgets/WootWriter/AudioRecorder.vue';
import WootMessageEditor from 'dashboard/components/widgets/WootWriter/Editor.vue';

const props = defineProps({
  modelValue: { type: Array, required: true },
  audioRecordFormat: { type: String, required: true },
  allowedFileTypes: { type: String, default: '' },
  conversationId: { type: [Number, String], default: '' },
  channelType: { type: String, default: '' },
  medium: { type: String, default: '' },
  variables: { type: Object, default: () => ({}) },
  richEditor: { type: Boolean, default: false },
  uploading: { type: Boolean, default: false },
});

const emit = defineEmits(['update:modelValue', 'upload']);
const recordingIndex = ref(null);
const recordingDuration = ref('00:00');
const audioRecorders = ref([]);
const copy = Object.freeze({
  message: 'Mensagem',
  interval: 'Envio 10 segundos após a anterior',
  limit: 'Limite de 5 mensagens por contato neste agendamento.',
});

const items = computed(() => props.modelValue);

const updateItem = (index, patch) => {
  const next = props.modelValue.map((item, itemIndex) =>
    itemIndex === index ? { ...item, ...patch } : item
  );
  emit('update:modelValue', next);
};

const addItem = () => {
  if (props.modelValue.length >= 5) return;
  emit('update:modelValue', [
    ...props.modelValue,
    {
      content: '',
      content_type: 'text',
      content_attributes: {},
      attachments: [],
      voice_message: false,
    },
  ]);
};

const removeItem = index => {
  if (props.modelValue.length === 1) return;
  emit(
    'update:modelValue',
    props.modelValue.filter((_, itemIndex) => itemIndex !== index)
  );
};

const removeAttachment = (itemIndex, attachmentIndex) => {
  const attachments = items.value[itemIndex].attachments.filter(
    (_, index) => index !== attachmentIndex
  );
  const voiceMessage = attachments.some(attachment => attachment.voiceMessage);
  updateItem(itemIndex, { attachments, voice_message: voiceMessage });
};

const beginRecording = index => {
  recordingDuration.value = '00:00';
  recordingIndex.value = index;
};

const stopRecording = index => {
  audioRecorders.value[index]?.stopRecording();
};

const finishRecording = (file, index) => {
  recordingIndex.value = null;
  emit('upload', {
    index,
    file: { ...file, isRecordedAudio: true },
    voiceMessage: true,
  });
};

const onFile = (file, index) => {
  if (!file) return;
  emit('upload', { index, file, voiceMessage: false });
};
</script>

<template>
  <div class="flex flex-col gap-4">
    <article
      v-for="(item, index) in items"
      :key="item.id || index"
      class="flex flex-col gap-3 p-3 rounded-xl border border-n-weak bg-n-alpha-2"
    >
      <header class="flex items-center justify-between gap-3">
        <div class="flex items-center gap-2">
          <span
            class="flex items-center justify-center text-xs font-semibold rounded-full size-6 bg-n-brand text-white"
          >
            {{ index + 1 }}
          </span>
          <div>
            <p class="mb-0 text-sm font-medium text-n-slate-12">
              {{ `${copy.message} ${index + 1}` }}
            </p>
            <p v-if="index" class="mb-0 text-xs text-n-slate-11">
              {{ copy.interval }}
            </p>
          </div>
        </div>
        <Button
          v-if="items.length > 1"
          icon="i-lucide-trash-2"
          color="ruby"
          variant="ghost"
          size="xs"
          @click="removeItem(index)"
        />
      </header>

      <div
        v-if="richEditor"
        class="rounded-lg border border-n-weak bg-n-solid-2"
      >
        <WootMessageEditor
          :model-value="item.content"
          :conversation-id="conversationId"
          :editor-id="`scheduled-message-editor-${index}`"
          class="input popover-prosemirror-menu"
          :min-height="3"
          :channel-type="channelType"
          :medium="medium"
          :variables="variables"
          enable-variables
          @update:model-value="updateItem(index, { content: $event })"
        />
      </div>
      <TextArea
        v-else
        :model-value="item.content"
        label="Mensagem"
        :max-length="10000"
        resize
        min-height="6rem"
        show-character-count
        @update:model-value="updateItem(index, { content: $event })"
      />

      <div
        v-if="recordingIndex === index"
        class="flex flex-col gap-2 p-2 rounded-lg border border-n-weak bg-n-solid-2"
      >
        <AudioRecorder
          :ref="element => (audioRecorders[index] = element)"
          :audio-record-format="audioRecordFormat"
          @recorder-progress-changed="recordingDuration = $event"
          @finish-record="finishRecording($event, index)"
          @record-error="recordingIndex = null"
        />
        <Button
          :label="`Parar gravação · ${recordingDuration}`"
          icon="i-lucide-square"
          color="ruby"
          variant="faded"
          size="sm"
          @click="stopRecording(index)"
        />
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <FileUpload
          :input-id="`scheduled-message-attachment-${index}`"
          :accept="allowedFileTypes"
          multiple
          drop
          :drop-directory="false"
          @input-file="onFile($event, index)"
        >
          <Button
            label="Adicionar anexo"
            icon="i-lucide-paperclip"
            color="slate"
            variant="outline"
            size="sm"
            :is-loading="uploading"
          />
        </FileUpload>
        <Button
          label="Gravar áudio"
          icon="i-lucide-mic"
          color="slate"
          variant="outline"
          size="sm"
          :disabled="recordingIndex !== null"
          @click="beginRecording(index)"
        />
      </div>

      <div v-if="item.attachments.length" class="flex flex-col gap-2">
        <div
          v-for="(attachment, attachmentIndex) in item.attachments"
          :key="attachment.signedId || `${index}-${attachmentIndex}`"
          class="flex items-center justify-between gap-3 p-2 rounded-lg bg-n-alpha-2"
        >
          <span class="flex items-center min-w-0 gap-2 text-sm text-n-slate-12">
            <Icon
              :icon="
                attachment.voiceMessage
                  ? 'i-lucide-audio-lines'
                  : 'i-lucide-file'
              "
              class="size-4 shrink-0"
            />
            <span class="truncate">{{
              attachment.name || 'Anexo existente'
            }}</span>
          </span>
          <Button
            icon="i-lucide-x"
            color="slate"
            variant="ghost"
            size="xs"
            @click="removeAttachment(index, attachmentIndex)"
          />
        </div>
      </div>
    </article>

    <Button
      v-if="items.length < 5"
      :label="`Adicionar mensagem (${items.length}/5)`"
      icon="i-lucide-plus"
      color="blue"
      variant="outline"
      size="sm"
      class="self-start"
      @click="addItem"
    />
    <p v-else class="mb-0 text-xs text-n-slate-11">
      {{ copy.limit }}
    </p>
  </div>
</template>
