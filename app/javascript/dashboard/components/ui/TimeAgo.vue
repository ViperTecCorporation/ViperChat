<script>
const MINUTE_IN_MILLI_SECONDS = 60000;
const HOUR_IN_MILLI_SECONDS = MINUTE_IN_MILLI_SECONDS * 60;
const DAY_IN_MILLI_SECONDS = HOUR_IN_MILLI_SECONDS * 24;

import {
  dynamicTime,
  dateFormat,
  shortTimestamp,
} from 'shared/helpers/timeHelper';
import { formatDistanceToNow, fromUnixTime } from 'date-fns';
import { ptBR } from 'date-fns/locale';

export default {
  name: 'TimeAgo',
  props: {
    showCreatedAt: {
      type: Boolean,
      default: true,
    },
    isAutoRefreshEnabled: {
      type: Boolean,
      default: true,
    },
    lastActivityTimestamp: {
      type: [String, Date, Number],
      default: '',
    },
    createdAtTimestamp: {
      type: [String, Date, Number],
      default: '',
    },
    conversationId: {
      type: [String, Number],
      default: '',
    },
  },
  data() {
    return {
      lastActivityAtTimeAgo: dynamicTime(this.lastActivityTimestamp),
      createdAtTimeAgo: dynamicTime(this.createdAtTimestamp),
      timer: null,
    };
  },
  computed: {
    isPortuguese() {
      return this.$i18n.locale.replace('_', '-').startsWith('pt');
    },
    lastActivityTime() {
      return this.compactTime(this.lastActivityAtTimeAgo);
    },
    createdAtTime() {
      return this.compactTime(this.createdAtTimeAgo);
    },
    createdAt() {
      const createdTimeDiff = Date.now() - this.createdAtTimestamp * 1000;
      const isBeforeAMonth = createdTimeDiff > DAY_IN_MILLI_SECONDS * 30;
      return !isBeforeAMonth
        ? `${this.$t('CHAT_LIST.CHAT_TIME_STAMP.CREATED.LATEST')} ${this.relativeTime(
            this.createdAtTimeAgo,
            this.createdAtTimestamp
          )}`
        : `${this.$t('CHAT_LIST.CHAT_TIME_STAMP.CREATED.OLDEST')} ${this.absoluteDate(
            this.createdAtTimestamp
          )}`;
    },
    lastActivity() {
      const lastActivityTimeDiff =
        Date.now() - this.lastActivityTimestamp * 1000;
      const isNotActive = lastActivityTimeDiff > DAY_IN_MILLI_SECONDS * 30;
      return !isNotActive
        ? `${this.$t('CHAT_LIST.CHAT_TIME_STAMP.LAST_ACTIVITY.ACTIVE')} ${this.relativeTime(
            this.lastActivityAtTimeAgo,
            this.lastActivityTimestamp
          )}`
        : `${this.$t(
            'CHAT_LIST.CHAT_TIME_STAMP.LAST_ACTIVITY.NOT_ACTIVE'
          )} ${this.absoluteDate(this.lastActivityTimestamp)}`;
    },
    tooltipText() {
      return this.showCreatedAt
        ? `${this.createdAt} • ${this.lastActivity}`
        : this.lastActivity;
    },
  },
  watch: {
    lastActivityTimestamp() {
      this.lastActivityAtTimeAgo = dynamicTime(this.lastActivityTimestamp);
    },
    createdAtTimestamp() {
      this.createdAtTimeAgo = dynamicTime(this.createdAtTimestamp);
    },
    conversationId() {
      // Reset display values and timer when the row is recycled to a different conversation.
      this.lastActivityAtTimeAgo = dynamicTime(this.lastActivityTimestamp);
      this.createdAtTimeAgo = dynamicTime(this.createdAtTimestamp);
      if (this.isAutoRefreshEnabled) {
        clearTimeout(this.timer);
        this.createTimer();
      }
    },
  },
  mounted() {
    if (this.isAutoRefreshEnabled) {
      this.createTimer();
    }
  },
  unmounted() {
    clearTimeout(this.timer);
  },
  methods: {
    compactTime(time) {
      const compact = shortTimestamp(
        this.isPortuguese ? time.replace(/^(about|over|almost)\s+/, '') : time
      ).trim();
      if (!this.isPortuguese) return compact;
      return compact
        .replace(/^now$/, 'agora')
        .replace(/y$/, 'a')
        .replace(
          /(\d+)mo$/,
          (_, months) => `${months}${Number(months) === 1 ? 'mês' : 'meses'}`
        );
    },
    relativeTime(time, timestamp) {
      if (!this.isPortuguese) return time;
      if (shortTimestamp(time) === 'now') return 'agora';
      return formatDistanceToNow(fromUnixTime(Number(timestamp)), {
        addSuffix: true,
        locale: ptBR,
      });
    },
    absoluteDate(timestamp) {
      if (!this.isPortuguese) return dateFormat(timestamp);
      return new Intl.DateTimeFormat('pt-BR', {
        day: '2-digit',
        month: '2-digit',
        year: 'numeric',
      }).format(fromUnixTime(Number(timestamp)));
    },
    createTimer() {
      this.timer = setTimeout(() => {
        this.lastActivityAtTimeAgo = dynamicTime(this.lastActivityTimestamp);
        this.createdAtTimeAgo = dynamicTime(this.createdAtTimestamp);
        this.createTimer();
      }, this.refreshTime());
    },
    refreshTime() {
      const timeDiff = Date.now() - this.lastActivityTimestamp * 1000;
      if (timeDiff > DAY_IN_MILLI_SECONDS) {
        return DAY_IN_MILLI_SECONDS;
      }
      if (timeDiff > HOUR_IN_MILLI_SECONDS) {
        return HOUR_IN_MILLI_SECONDS;
      }

      return MINUTE_IN_MILLI_SECONDS;
    },
  },
};
</script>

<template>
  <div
    v-tooltip.top="{
      content: tooltipText,
      delay: { show: 1000, hide: 0 },
    }"
    class="ml-auto leading-4 text-xxs text-n-slate-10 hover:text-n-slate-11"
  >
    <span>{{
      showCreatedAt
        ? `${createdAtTime} • ${lastActivityTime}`
        : lastActivityTime
    }}</span>
  </div>
</template>
