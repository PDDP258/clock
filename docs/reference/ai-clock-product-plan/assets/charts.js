(function() {
  var style = getComputedStyle(document.documentElement);
  var accent = style.getPropertyValue('--accent').trim();
  var accent2 = style.getPropertyValue('--accent2').trim();
  var ink = style.getPropertyValue('--ink').trim();
  var muted = style.getPropertyValue('--muted').trim();
  var rule = style.getPropertyValue('--rule').trim();
  var bg2 = style.getPropertyValue('--bg2').trim();
  var bg = style.getPropertyValue('--bg').trim();

  // --- Chart: Radar comparison ---
  var radarEl = document.getElementById('chart-radar');
  if (radarEl) {
    var radarChart = echarts.init(radarEl, null, { renderer: 'svg' });
    radarChart.setOption({
      animation: false,
      backgroundColor: 'transparent',
      tooltip: { trigger: 'item', appendToBody: true },
      legend: {
        bottom: 0,
        textStyle: { color: muted, fontSize: 12 },
        data: ['Forest', '番茄ToDo', 'TickTick', 'Focus Timer', 'AI Clock (目标)']
      },
      radar: {
        center: ['50%', '48%'],
        radius: '65%',
        indicator: [
          { name: '免触屏', max: 10 },
          { name: '数据统计', max: 10 },
          { name: '计时模式', max: 10 },
          { name: '激励体系', max: 10 },
          { name: '跨平台', max: 10 },
          { name: '扩展性', max: 10 }
        ],
        axisName: { color: muted, fontSize: 11 },
        splitArea: { areaStyle: { color: ['transparent'] } },
        splitLine: { lineStyle: { color: rule } },
        axisLine: { lineStyle: { color: rule } }
      },
      series: [{
        type: 'radar',
        data: [
          {
            value: [0, 5, 3, 8, 7, 3],
            name: 'Forest',
            lineStyle: { color: '#4ecb71', width: 1.5 },
            areaStyle: { color: 'rgba(78,203,113,0.1)' },
            itemStyle: { color: '#4ecb71' }
          },
          {
            value: [0, 9, 4, 5, 3, 3],
            name: '番茄ToDo',
            lineStyle: { color: '#f6685e', width: 1.5 },
            areaStyle: { color: 'rgba(246,104,94,0.1)' },
            itemStyle: { color: '#f6685e' }
          },
          {
            value: [0, 4, 3, 4, 9, 5],
            name: 'TickTick',
            lineStyle: { color: '#4770ff', width: 1.5 },
            areaStyle: { color: 'rgba(71,112,255,0.1)' },
            itemStyle: { color: '#4770ff' }
          },
          {
            value: [5, 3, 2, 2, 1, 1],
            name: 'Focus Timer',
            lineStyle: { color: '#ff9800', width: 1.5 },
            areaStyle: { color: 'rgba(255,152,0,0.1)' },
            itemStyle: { color: '#ff9800' }
          },
          {
            value: [10, 9, 9, 9, 5, 10],
            name: 'AI Clock (目标)',
            lineStyle: { color: accent, width: 2.5 },
            areaStyle: { color: 'rgba(124,92,252,0.2)' },
            itemStyle: { color: accent }
          }
        ]
      }]
    });
    window.addEventListener('resize', function() { radarChart.resize(); });
  }

  // --- Chart: Feature Map (Treemap) ---
  var featureEl = document.getElementById('chart-feature-map');
  if (featureEl) {
    var featureChart = echarts.init(featureEl, null, { renderer: 'svg' });
    featureChart.setOption({
      animation: false,
      backgroundColor: 'transparent',
      tooltip: {
        trigger: 'item',
        appendToBody: true,
        formatter: function(p) {
          return '<strong>' + p.name + '</strong><br/>' + (p.data.desc || '');
        }
      },
      series: [{
        type: 'treemap',
        width: '100%',
        height: '100%',
        roam: false,
        nodeClick: false,
        breadcrumb: { show: false },
        itemStyle: {
          borderColor: bg,
          borderWidth: 3,
          gapWidth: 3
        },
        label: {
          show: true,
          formatter: function(p) {
            return '{name|' + p.name + '}';
          },
          rich: {
            name: { fontSize: 13, color: '#fff', fontWeight: 'bold', padding: [4, 8] }
          }
        },
        upperLabel: { show: true, height: 28, color: muted, fontSize: 12 },
        levels: [
          { color: [accent, accent2, muted] },
          { colorSaturation: [0.3, 0.6] }
        ],
        data: [
          {
            name: 'AI Clock 核心功能',
            children: [
              {
                name: '实体按键控制',
                value: 25,
                desc: '耳机/蓝牙按键控制计时，免触屏操作',
                itemStyle: { color: accent }
              },
              {
                name: '多模式计时',
                value: 20,
                desc: '番茄钟/深度工作/正计时/Flowtime/自定义',
                itemStyle: { color: '#6a4ee0' }
              },
              {
                name: '数据统计',
                value: 18,
                desc: '日/周/月/年趋势、效率曲线、最佳时段识别',
                itemStyle: { color: '#5a42d4' }
              },
              {
                name: '后台计时',
                value: 12,
                desc: '前台服务+通知栏快捷控制',
                itemStyle: { color: '#4a36c8' }
              },
              {
                name: '成就系统',
                value: 10,
                desc: '连续打卡、等级徽章、每周回顾报告',
                itemStyle: { color: accent2 }
              },
              {
                name: '白噪音',
                value: 8,
                desc: '内置专注音效，配合计时使用',
                itemStyle: { color: '#00b895' }
              },
              {
                name: '主题定制',
                value: 7,
                desc: '自定义颜色、字体、背景',
                itemStyle: { color: '#009c7a' }
              }
            ]
          }
        ]
      }]
    });
    window.addEventListener('resize', function() { featureChart.resize(); });
  }
})();