<script setup>
import { computed } from 'vue';
import BarChart from 'shared/components/charts/BarChart.vue';
const props = defineProps({
  componentData: {
    type: Object,
    default: () => ({}),
  },
});

const prepareData = sourceData => {
  var labels = [];
  var data = [];
  sourceData.forEach(item => {
    labels.push(item[0]);
    data.push(item[1]);
  });
  return {
    labels,
    datasets: [
      {
        type: 'bar',
        backgroundColor: 'rgb(31, 147, 255)',
        yAxisID: 'y',
        label: props.componentData.labels?.conversations || 'Conversations',
        data: data,
      },
    ],
  };
};

const chartData = computed(() => {
  return prepareData(props.componentData.chartData);
});

const {
  accountsCount,
  usersCount,
  inboxesCount,
  conversationsCount,
  labels = {},
} = props.componentData;
</script>

<template>
  <div class="w-full h-full">
    <header class="main-content__header" role="banner">
      <h1 id="page-title" class="main-content__page-title">
        {{ labels.title || 'Admin Dashboard' }}
      </h1>
    </header>

    <section class="main-content__body main-content__body--flush">
      <div class="grid grid-cols-1 sm:grid-cols-2 xl:grid-cols-4 gap-4">
        <div class="report-card">
          <div class="metric">{{ accountsCount }}</div>
          <div>{{ labels.accounts || 'Accounts' }}</div>
        </div>
        <div class="report-card">
          <div class="metric">{{ usersCount }}</div>
          <div>{{ labels.users || 'Users' }}</div>
        </div>
        <div class="report-card">
          <div class="metric">{{ inboxesCount }}</div>
          <div>{{ labels.inboxes || 'Inboxes' }}</div>
        </div>
        <div class="report-card">
          <div class="metric">{{ conversationsCount }}</div>
          <div>{{ labels.conversations || 'Conversations' }}</div>
        </div>
      </div>
    </section>
    <BarChart class="p-4 md:p-8 w-full max-h-[500px]" :collection="chartData" />
  </div>
</template>
