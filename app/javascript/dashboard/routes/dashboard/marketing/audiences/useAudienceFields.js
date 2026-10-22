import { computed, onMounted } from 'vue';
import { useI18n } from 'vue-i18n';
import format from 'date-fns/format';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { ORIGEM_OPTIONS } from 'dashboard/helper/origemOptions';

// The fields an audience rule accepts (the same ones Audiences::Resolver
// supports), their choices and how a saved condition reads in the panel.
// A condition is the conversation filter's payload:
// { attribute_key, filter_operator, values: [value], query_operator }.
export const FIELD_KEYS = [
  'labels',
  'funnel_stage_id',
  'loss_reason_id',
  'origem',
  'inbox_id',
  'assignee_id',
  'status',
];

const STATUSES = ['open', 'resolved', 'pending', 'snoozed'];

export function useAudienceFields() {
  const { t } = useI18n();
  const store = useStore();

  const labels = useMapGetter('labels/getLabels');
  const stages = useMapGetter('funnelStages/getFunnelStages');
  const lossReasons = useMapGetter('lossReasons/getLossReasons');
  const inboxes = useMapGetter('inboxes/getInboxes');
  const agents = useMapGetter('agents/getAgents');

  onMounted(() => {
    store.dispatch('labels/get');
    store.dispatch('funnelStages/get');
    store.dispatch('lossReasons/get');
    store.dispatch('inboxes/get');
    store.dispatch('agents/get');
  });

  const fieldLabels = computed(() => ({
    labels: t('AUDIENCES.FIELDS.LABELS'),
    funnel_stage_id: t('AUDIENCES.FIELDS.FUNNEL_STAGE_ID'),
    loss_reason_id: t('AUDIENCES.FIELDS.LOSS_REASON_ID'),
    origem: t('AUDIENCES.FIELDS.ORIGEM'),
    inbox_id: t('AUDIENCES.FIELDS.INBOX_ID'),
    assignee_id: t('AUDIENCES.FIELDS.ASSIGNEE_ID'),
    status: t('AUDIENCES.FIELDS.STATUS'),
  }));
  const fieldLabel = key => fieldLabels.value[key] || key;

  const statusLabels = computed(() => ({
    open: t('AUDIENCES.STATUS.OPEN'),
    resolved: t('AUDIENCES.STATUS.RESOLVED'),
    pending: t('AUDIENCES.STATUS.PENDING'),
    snoozed: t('AUDIENCES.STATUS.SNOOZED'),
  }));

  const fields = computed(() =>
    FIELD_KEYS.map(key => ({ value: key, label: fieldLabel(key) }))
  );

  const optionsFor = key => {
    switch (key) {
      case 'labels':
        return (labels.value || []).map(l => ({
          value: l.title,
          label: l.title,
        }));
      case 'funnel_stage_id':
        return (stages.value || []).map(s => ({ value: s.id, label: s.name }));
      case 'loss_reason_id':
        return (lossReasons.value || []).map(r => ({
          value: r.id,
          label: r.name,
        }));
      case 'origem':
        return ORIGEM_OPTIONS.map(o => ({ value: o, label: o }));
      case 'inbox_id':
        return (inboxes.value || []).map(i => ({ value: i.id, label: i.name }));
      case 'assignee_id':
        return (agents.value || []).map(a => ({ value: a.id, label: a.name }));
      case 'status':
        return STATUSES.map(s => ({ value: s, label: statusLabels.value[s] }));
      default:
        return [];
    }
  };

  // Labels read "inclui / não inclui"; every other field "é / não é".
  const operatorsFor = key =>
    key === 'labels'
      ? [
          { value: 'equal_to', label: t('AUDIENCES.OPERATORS.INCLUDES') },
          { value: 'not_equal_to', label: t('AUDIENCES.OPERATORS.EXCLUDES') },
        ]
      : [
          { value: 'equal_to', label: t('AUDIENCES.OPERATORS.IS') },
          { value: 'not_equal_to', label: t('AUDIENCES.OPERATORS.IS_NOT') },
        ];

  const describe = condition => {
    const key = condition.attribute_key;
    const operator = operatorsFor(key).find(
      o => o.value === condition.filter_operator
    );
    const value = (condition.values || []).map(v => {
      const option = optionsFor(key).find(o => String(o.value) === String(v));
      return option ? option.label : v;
    });
    return `${fieldLabel(key)} ${operator?.label || ''} ${value.join(', ')}`;
  };

  const formatDate = value => format(new Date(`${value}T00:00:00`), 'dd/MM');

  const describeWindow = (window = {}) => {
    if (window.type === 'last_days') {
      return t('AUDIENCES.WINDOW.LAST_DAYS', { days: window.days });
    }
    if (window.type === 'range') {
      // Still being filled in: no dates to show yet.
      if (!window.from || !window.to) return t('AUDIENCES.FORM.WINDOW_RANGE');
      return t('AUDIENCES.WINDOW.RANGE', {
        from: formatDate(window.from),
        to: formatDate(window.to),
      });
    }
    return t('AUDIENCES.WINDOW.ALL');
  };

  return { fields, optionsFor, operatorsFor, describe, describeWindow };
}
