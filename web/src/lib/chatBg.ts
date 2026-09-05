import type { CSSProperties } from 'react'
import type { ChatBg, ChatTheme } from '../api'

export type ChatBgPreset = {
  id: string
  label: string
  css: string
  /** 出处说明（如 uiGradients 名称） */
  credit?: string
}

/**
 * 聊天背景渐变预设（精选少量、辨识度高）。
 * 色值来自 [uiGradients](https://github.com/ghosh/uiGradients) 的 soft 系配方。
 */
export const CHAT_BG_GRADIENTS: ChatBgPreset[] = [
  {
    id: 'sky',
    label: '天色',
    credit: 'Colors Of Sky',
    css: 'linear-gradient(160deg, #E0EAFC 0%, #CFDEF3 100%)',
  },
  {
    id: 'water',
    label: '水色',
    credit: 'Digital Water',
    css: 'linear-gradient(135deg, #74EBD5 0%, #ACB6E5 100%)',
  },
  {
    id: 'shore',
    label: '海岸',
    credit: 'Shore',
    css: 'linear-gradient(120deg, #70E1F5 0%, #FFD194 100%)',
  },
  {
    id: 'peach',
    label: '蜜桃',
    credit: 'Roseanna',
    css: 'linear-gradient(135deg, #FFAFBD 0%, #FFC3A0 100%)',
  },
  {
    id: 'delicate',
    label: '丁香',
    credit: 'Delicate',
    css: 'linear-gradient(135deg, #D3CCE3 0%, #E9E4F0 100%)',
  },
  {
    id: 'grass',
    label: '青草',
    credit: 'Dusty Grass',
    css: 'linear-gradient(135deg, #D4FC79 0%, #96E6A1 100%)',
  },
  {
    id: 'breeze',
    label: '微风',
    credit: 'Summer Breeze',
    css: 'linear-gradient(135deg, #FBED96 0%, #ABECD6 100%)',
  },
  {
    id: 'almost',
    label: '暮霞',
    credit: 'Almost',
    css: 'linear-gradient(135deg, #DDD6F3 0%, #FAACA8 100%)',
  },
]

/** 旧预设 id → 新 id，避免已保存偏好失效 */
const GRADIENT_ALIASES: Record<string, string> = {
  mint: 'grass',
  aurora: 'water',
  ocean: 'shore',
  rose: 'peach',
  lavender: 'delicate',
  violet: 'delicate',
  sunset: 'almost',
  lemon: 'breeze',
  matcha: 'grass',
  sand: 'shore',
  aqua: 'water',
  blossom: 'peach',
}

/**
 * 中国传统色配方：色名与 HEX 均取自 https://zhongguose.com/colors.json（官网数据）。
 * 聊天底色会经 softChatHex 淡化，保证气泡可读。
 */
export type ChineseColorRecipe = {
  id: string
  name: string
  /** 官网正色 HEX */
  hex: string
}

export const CHINESE_COLOR_RECIPES: ChineseColorRecipe[] = [
  { id: 'yuebai', name: '月白', hex: '#EEF7F2' },
  { id: 'rubai', name: '乳白', hex: '#F9F4DC' },
  { id: 'xiangyabai', name: '象牙白', hex: '#FFFEF8' },
  { id: 'fenbai', name: '粉白', hex: '#FBF2E3' },
  { id: 'yudubai', name: '鱼肚白', hex: '#F7F4ED' },
  { id: 'yinbai', name: '银白', hex: '#F1F0ED' },
  { id: 'ouhe', name: '藕荷', hex: '#EDC3AE' },
  { id: 'dingxiangdanzi', name: '丁香淡紫', hex: '#E9D7DF' },
  { id: 'danqianniuzi', name: '淡牵牛紫', hex: '#D1C2D3' },
  { id: 'fengxinzi', name: '凤信紫', hex: '#C8ADC4' },
  { id: 'shuihong', name: '水红', hex: '#F1C4CD' },
  { id: 'hehuanhong', name: '合欢红', hex: '#F0A1A8' },
  { id: 'yuantianlan', name: '远天蓝', hex: '#D0DFE6' },
  { id: 'haitianlan', name: '海天蓝', hex: '#C6E6E8' },
  { id: 'hushuilan', name: '湖水蓝', hex: '#B0D5DF' },
  { id: 'xinglan', name: '星蓝', hex: '#93B5CF' },
  { id: 'jiqing', name: '霁青', hex: '#63BBD0' },
  { id: 'qunqing', name: '群青', hex: '#1772B4' },
  { id: 'dianqing', name: '靛青', hex: '#1661AB' },
  { id: 'huaqing', name: '花青', hex: '#2376B7' },
  { id: 'jingtailan', name: '景泰蓝', hex: '#2775B6' },
  { id: 'pinlan', name: '品蓝', hex: '#2B73AF' },
  { id: 'zhuhuanglv', name: '竹篁绿', hex: '#B9DEC9' },
  { id: 'fenlv', name: '粉绿', hex: '#83CBAC' },
  { id: 'shilv', name: '石绿', hex: '#57C3C2' },
  { id: 'ailv', name: '艾绿', hex: '#CAD3C3' },
  { id: 'songshuanglv', name: '松霜绿', hex: '#83A78D' },
  { id: 'yalv', name: '芽绿', hex: '#96C24E' },
  { id: 'conglv', name: '葱绿', hex: '#40A070' },
  { id: 'tenghuang', name: '藤黄', hex: '#FFD111' },
  { id: 'xinghuang', name: '杏黄', hex: '#F28E16' },
  { id: 'qiantuose', name: '浅驼色', hex: '#E2C17C' },
  { id: 'haitanghong', name: '海棠红', hex: '#F03752' },
  { id: 'yanzhihong', name: '胭脂红', hex: '#F03F24' },
  { id: 'pinhong', name: '品红', hex: '#EF3473' },
  { id: 'zhuhong', name: '朱红', hex: '#ED5126' },
  { id: 'tuose', name: '驼色', hex: '#66462A' },
]

/** 旧中国色 id → 新 id */
const CHINESE_COLOR_ALIASES: Record<string, string> = {
  shuangse: 'songshuanglv',
  gaose: 'yudubai',
  ouhese: 'ouhe',
  xueqing: 'fengxinzi',
  dingxiang: 'dingxiangdanzi',
  tianqing: 'jiqing',
  dailan: 'dianqing',
  piaose: 'fenlv',
  qingbi: 'shilv',
  zhuqing: 'songshuanglv',
  songhua: 'yalv',
  xiangse: 'tenghuang',
  haitang: 'haitanghong',
  yanzhi: 'yanzhihong',
  zhusha: 'yanzhihong',
  chase: 'tuose',
  mogui: 'ailv',
  mose: 'tuose',
}

/** 主题色（中国色官网色值） */
export const THEME_ACCENT_PRESETS = [
  { id: 'jiqing', label: '霁青', hex: '#63BBD0' },
  { id: 'qunqing', label: '群青', hex: '#1772B4' },
  { id: 'dianqing', label: '靛青', hex: '#1661AB' },
  { id: 'jingtailan', label: '景泰蓝', hex: '#2775B6' },
  { id: 'conglv', label: '葱绿', hex: '#40A070' },
  { id: 'yalv', label: '芽绿', hex: '#96C24E' },
  { id: 'fengxinzi', label: '凤信紫', hex: '#C8ADC4' },
  { id: 'haitanghong', label: '海棠红', hex: '#F03752' },
  { id: 'yanzhihong', label: '胭脂红', hex: '#F03F24' },
  { id: 'pinhong', label: '品红', hex: '#EF3473' },
  { id: 'tenghuang', label: '藤黄', hex: '#FFD111' },
  { id: 'xinghuang', label: '杏黄', hex: '#F28E16' },
]

/** 我的气泡（中国色） */
export const THEME_BUBBLE_MINE_PRESETS = [
  { id: 'zhuhuanglv', label: '竹篁绿', hex: '#B9DEC9' },
  { id: 'fenlv', label: '粉绿', hex: '#83CBAC' },
  { id: 'shilv', label: '石绿', hex: '#57C3C2' },
  { id: 'yalv', label: '芽绿', hex: '#96C24E' },
  { id: 'shuihong', label: '水红', hex: '#F1C4CD' },
  { id: 'hehuanhong', label: '合欢红', hex: '#F0A1A8' },
  { id: 'dingxiangdanzi', label: '丁香淡紫', hex: '#E9D7DF' },
  { id: 'hushuilan', label: '湖水蓝', hex: '#B0D5DF' },
  { id: 'rubai', label: '乳白', hex: '#F9F4DC' },
]

/** 对方气泡（中国色浅色） */
export const THEME_BUBBLE_PEER_PRESETS = [
  { id: 'xiangyabai', label: '象牙白', hex: '#FFFEF8' },
  { id: 'yuebai', label: '月白', hex: '#EEF7F2' },
  { id: 'fenbai', label: '粉白', hex: '#FBF2E3' },
  { id: 'yudubai', label: '鱼肚白', hex: '#F7F4ED' },
  { id: 'yinbai', label: '银白', hex: '#F1F0ED' },
  { id: 'yuantianlan', label: '远天蓝', hex: '#D0DFE6' },
  { id: 'haitianlan', label: '海天蓝', hex: '#C6E6E8' },
  { id: 'ailv', label: '艾绿', hex: '#CAD3C3' },
]

export function resolveGradientPreset(id?: string | null): ChatBgPreset | undefined {
  if (!id) return undefined
  const resolved = GRADIENT_ALIASES[id] || id
  return CHAT_BG_GRADIENTS.find((g) => g.id === resolved)
}

export function resolveChineseColor(id?: string | null): ChineseColorRecipe | undefined {
  if (!id) return undefined
  const resolved = CHINESE_COLOR_ALIASES[id] || id
  return CHINESE_COLOR_RECIPES.find((c) => c.id === resolved)
}

export function parseHex(hex: string): { r: number; g: number; b: number } | null {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim())
  if (!m) return null
  const n = parseInt(m[1], 16)
  return { r: (n >> 16) & 255, g: (n >> 8) & 255, b: n & 255 }
}

export function toHex(r: number, g: number, b: number): string {
  const c = (n: number) =>
    Math.max(0, Math.min(255, Math.round(n)))
      .toString(16)
      .padStart(2, '0')
  return `#${c(r)}${c(g)}${c(b)}`.toUpperCase()
}

/** 正色向白混合，作聊天背景用的浅色配方。 */
export function softChatHex(hex: string, towardWhite = 0.78): string {
  const rgb = parseHex(hex)
  if (!rgb) return '#F5F5F5'
  const t = Math.max(0, Math.min(1, towardWhite))
  return toHex(
    rgb.r + (255 - rgb.r) * t,
    rgb.g + (255 - rgb.g) * t,
    rgb.b + (255 - rgb.b) * t,
  )
}

export function chatBgCss(bg?: ChatBg | null): string {
  if (!bg || bg.kind === 'default') return 'var(--im-color-chat, #f5f5f5)'
  if (bg.kind === 'color' && bg.hex) {
    const recipe = resolveChineseColor(bg.id)
    // 中国色：轻柔化即可，过白会冲掉壁纸色，毛玻璃也看不出层次
    if (recipe) return softChatHex(recipe.hex, 0.22)
    return bg.hex
  }
  if (bg.kind === 'gradient' && bg.id) {
    const preset = resolveGradientPreset(bg.id)
    if (preset) return preset.css
  }
  return 'var(--im-color-chat, #f5f5f5)'
}

export function chatBgStyle(bg?: ChatBg | null): CSSProperties {
  if (bg?.kind === 'image' && bg.url) {
    return {
      backgroundColor: '#e8e8e8',
      backgroundImage: `url(${bg.url})`,
      backgroundSize: 'cover',
      backgroundPosition: 'center',
      backgroundRepeat: 'no-repeat',
    }
  }
  return { background: chatBgCss(bg) }
}

export function chatBgSummary(bg?: ChatBg | null): string {
  if (!bg || bg.kind === 'default') return '默认'
  if (bg.kind === 'color') {
    if (bg.id) {
      const r = resolveChineseColor(bg.id)
      if (r) return r.name
    }
    return bg.hex?.toUpperCase() || '自定义色'
  }
  if (bg.kind === 'gradient') {
    return resolveGradientPreset(bg.id)?.label || '渐变'
  }
  if (bg.kind === 'image') return '自定义图片'
  return '默认'
}

export const THEME_TEXTURES = [
  { id: 'none', label: '无' },
  { id: 'dots', label: '点点' },
  { id: 'grid', label: '网格' },
  { id: 'paper', label: '纸纹' },
  { id: 'diagonal', label: '斜纹' },
] as const

export function resolveUserTheme(user: {
  chatTheme?: ChatTheme | null
  chatBg?: ChatBg | null
}): ChatTheme | null {
  if (user.chatTheme) return user.chatTheme
  if (user.chatBg) return { background: user.chatBg }
  return null
}

function mixHex(hex: string, toward: number, amount: number): string {
  const rgb = parseHex(hex)
  if (!rgb) return hex
  return toHex(
    rgb.r + (toward - rgb.r) * amount,
    rgb.g + (toward - rgb.g) * amount,
    rgb.b + (toward - rgb.b) * amount,
  )
}

function hexAlpha(hex: string, alpha: number): string {
  const rgb = parseHex(hex)
  if (!rgb) return hex
  const a = Math.max(0, Math.min(1, alpha))
  return `rgba(${rgb.r}, ${rgb.g}, ${rgb.b}, ${a})`
}

/** Ant / TDesign 式主题色：写入完整 brand 色板，驱动按钮 / Switch / Slider 等 */
function applyBrandPalette(vars: Record<string, string>, accent: string) {
  const c1 = mixHex(accent, 255, 0.92)
  const c2 = mixHex(accent, 255, 0.82)
  const c3 = mixHex(accent, 255, 0.68)
  const c4 = mixHex(accent, 255, 0.48)
  const c5 = mixHex(accent, 255, 0.28)
  const c6 = mixHex(accent, 255, 0.14) // hover（更浅）
  const c7 = accent // 主色
  const c8 = mixHex(accent, 0, 0.16) // active（更深）
  const c9 = mixHex(accent, 0, 0.28)
  const c10 = mixHex(accent, 0, 0.42)

  vars['--td-brand-color-1'] = c1
  vars['--td-brand-color-2'] = c2
  vars['--td-brand-color-3'] = c3
  vars['--td-brand-color-4'] = c4
  vars['--td-brand-color-5'] = c5
  vars['--td-brand-color-6'] = c6
  vars['--td-brand-color-7'] = c7
  vars['--td-brand-color-8'] = c8
  vars['--td-brand-color-9'] = c9
  vars['--td-brand-color-10'] = c10

  vars['--td-brand-color'] = c7
  vars['--td-brand-color-hover'] = c6
  vars['--td-brand-color-focus'] = c2
  vars['--td-brand-color-active'] = c8
  vars['--td-brand-color-disabled'] = c3
  vars['--td-brand-color-light'] = c1
  vars['--td-brand-color-light-hover'] = c2
  vars['--td-text-color-brand'] = c7
  vars['--td-text-color-link'] = c8

  vars['--im-color-primary'] = c7
  vars['--im-color-primary-deep'] = c8
  vars['--im-color-primary-soft'] = c1
  vars['--im-rail-active-bg'] = hexAlpha(accent, 0.28)
}

/** 有自定义背景时使用整窗壁纸层（含 PC 图片；焦点可偏到会话区）。 */
export function usesFrameWallpaper(theme?: ChatTheme | null): boolean {
  const bg = theme?.background
  return !!(bg && bg.kind !== 'default')
}

/** CSS 变量：主题色驱动组件；背景驱动整窗或房间（QQ 随心调） */
export function chatThemeVars(
  theme?: ChatTheme | null,
  opts?: { frameWallpaper?: boolean },
): CSSProperties {
  const vars: Record<string, string> = {}
  const accent = theme?.accent

  if (accent) {
    applyBrandPalette(vars, accent)
    vars['--im-theme-has-accent'] = '1'
    // 抽屉默认跟主题色浅底（壁纸模式下方可再覆盖）
    vars['--im-color-drawer-bg'] = softChatHex(accent, 0.92)
  }

  if (theme?.bubbleMine) {
    vars['--im-bubble-mine'] = theme.bubbleMine
  }
  if (theme?.bubblePeer) vars['--im-bubble-peer'] = theme.bubblePeer

  const hasBg = !!(theme?.background && theme.background.kind !== 'default')
  const frameWallpaper = opts?.frameWallpaper ?? hasBg
  const opacity = theme?.opacity
  const blur = theme?.blur

  // 整窗壁纸：侧栏/顶栏/输入栏半透明露出背景（不影响气泡）
  if (hasBg && frameWallpaper) {
    vars['--im-theme-has-wallpaper'] = '1'
    vars['--im-color-chat'] = 'transparent'
    const o = opacity != null ? Math.max(0, Math.min(1, opacity)) : 0.62
    const b = blur != null ? Math.max(0, Math.min(1, blur)) : 0.83
    // 透明度：仅面板底色 alpha
    vars['--im-theme-panel-opacity'] = String(Math.min(0.94, o))
    // 毛玻璃：0 → 无模糊；1 → 约 12px（默认约 10px）
    vars['--im-theme-blur'] = `${(b * 12).toFixed(1)}px`
    vars['--im-theme-saturate'] = String((1 + b * 0.2).toFixed(2))
    // 毛玻璃承托：统一偏白
    vars['--im-theme-panel'] = '#ffffff'

    const bg = theme!.background!
    if (bg.kind === 'color' && bg.hex) {
      const soft = softChatHex(bg.hex, 0.28)
      vars['--im-color-bg'] = softChatHex(bg.hex, 0.38)
      // 抽屉底：有主题色时跟主题；否则用背景色的很浅配方，避免会话区脏色块
      vars['--im-color-drawer-bg'] = accent
        ? softChatHex(accent, 0.9)
        : softChatHex(bg.hex, 0.78)
      vars['--im-color-surface'] = soft
    } else if (bg.kind === 'gradient') {
      // 外框用渐变首色近似
      const preset = resolveGradientPreset(bg.id)
      const tip = preset?.css.match(/#([0-9a-f]{6})/i)?.[0]
      if (tip) {
        vars['--im-color-bg'] = softChatHex(tip, 0.38)
        vars['--im-color-drawer-bg'] = accent
          ? softChatHex(accent, 0.9)
          : softChatHex(tip, 0.78)
      }
    } else if (bg.kind === 'image') {
      vars['--im-color-bg'] = '#d8d8d8'
      if (accent) {
        vars['--im-color-drawer-bg'] = softChatHex(accent, 0.9)
      }
    }
  }

  return vars as CSSProperties
}

export function chatThemeSummary(theme?: ChatTheme | null): string {
  if (!theme) return '默认'
  const parts: string[] = []
  if (theme.accent) parts.push('主题色')
  if (theme.bubbleMine || theme.bubblePeer) parts.push('气泡')
  if (theme.background) parts.push(chatBgSummary(theme.background))
  if (theme.texture && theme.texture !== 'none') parts.push('纹理')
  if (theme.opacity != null && theme.opacity < 1) parts.push('透明')
  if (theme.blur != null && theme.blur > 0) parts.push('毛玻璃')
  return parts.length ? parts.join(' · ') : '默认'
}


