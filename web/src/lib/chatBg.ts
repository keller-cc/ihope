import type { CSSProperties } from 'react'
import type { ChatBg } from '../api'

export type ChatBgPreset = {
  id: string
  label: string
  css: string
}

/** @deprecated kept so旧数据 gradient id 仍可渲染 */
export const CHAT_BG_GRADIENTS: ChatBgPreset[] = [
  {
    id: 'mint',
    label: '薄荷绿',
    css: 'linear-gradient(165deg, #c8f0de 0%, #e8f8f0 45%, #f5fcf8 100%)',
  },
  {
    id: 'sky',
    label: '天空蓝',
    css: 'linear-gradient(165deg, #b9e6ff 0%, #dff3ff 45%, #f2f9ff 100%)',
  },
  {
    id: 'peach',
    label: '蜜桃粉',
    css: 'linear-gradient(165deg, #ffd4c2 0%, #ffe8dc 45%, #fff6f0 100%)',
  },
  {
    id: 'lavender',
    label: '薰衣草紫',
    css: 'linear-gradient(165deg, #d9d0ff 0%, #ebe6ff 45%, #f7f5ff 100%)',
  },
  {
    id: 'lemon',
    label: '柠檬黄',
    css: 'linear-gradient(165deg, #ffe9a8 0%, #fff4cc 45%, #fffcef 100%)',
  },
  {
    id: 'rose',
    label: '蔷薇',
    css: 'linear-gradient(165deg, #ffc9d6 0%, #ffe0e8 45%, #fff5f8 100%)',
  },
  {
    id: 'aqua',
    label: '浅青',
    css: 'linear-gradient(165deg, #b8f0ef 0%, #daf7f6 45%, #f0fbfb 100%)',
  },
  {
    id: 'sand',
    label: '暖沙',
    css: 'linear-gradient(165deg, #ead9c0 0%, #f3e9d8 45%, #faf6ef 100%)',
  },
]

/**
 * 中国传统色配方（参考常见「中国色」色卡：色名 + 正色 HEX）。
 * 聊天背景使用 softChatHex 淡化后的色，避免过深影响阅读。
 */
export type ChineseColorRecipe = {
  id: string
  name: string
  /** 正色（配方） */
  hex: string
}

export const CHINESE_COLOR_RECIPES: ChineseColorRecipe[] = [
  { id: 'yuebai', name: '月白', hex: '#D6ECF0' },
  { id: 'shuangse', name: '霜色', hex: '#E9F1F6' },
  { id: 'gaose', name: '缟色', hex: '#F2ECDE' },
  { id: 'xiangyabai', name: '象牙白', hex: '#FFFBF0' },
  { id: 'ouhese', name: '藕荷', hex: '#E4C6D0' },
  { id: 'xueqing', name: '雪青', hex: '#B0A4E3' },
  { id: 'dingxiang', name: '丁香', hex: '#CCA4E3' },
  { id: 'tianqing', name: '天青', hex: '#88ADED' },
  { id: 'qunqing', name: '群青', hex: '#4C8DAE' },
  { id: 'dianqing', name: '靛青', hex: '#177CB0' },
  { id: 'dailan', name: '黛蓝', hex: '#425066' },
  { id: 'jiqing', name: '霁青', hex: '#1A6B8A' },
  { id: 'piaose', name: '缥色', hex: '#7FECAD' },
  { id: 'qingbi', name: '青碧', hex: '#48C0A3' },
  { id: 'zhuqing', name: '竹青', hex: '#789262' },
  { id: 'conglu', name: '葱绿', hex: '#9ED048' },
  { id: 'songhua', name: '松花', hex: '#BCE672' },
  { id: 'xiangse', name: '缃色', hex: '#F0C239' },
  { id: 'tenghuang', name: '藤黄', hex: '#FFB61E' },
  { id: 'haitang', name: '海棠', hex: '#DB5A6B' },
  { id: 'yanzhi', name: '胭脂', hex: '#9D2933' },
  { id: 'zhusha', name: '朱砂', hex: '#FF461F' },
  { id: 'tuose', name: '驼色', hex: '#A88462' },
  { id: 'chase', name: '茶色', hex: '#B35C44' },
  { id: 'mogui', name: '墨灰', hex: '#758A99' },
  { id: 'mose', name: '墨色', hex: '#50616D' },
]

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

export function rgbToHsv(r: number, g: number, b: number): { h: number; s: number; v: number } {
  r /= 255
  g /= 255
  b /= 255
  const max = Math.max(r, g, b)
  const min = Math.min(r, g, b)
  const d = max - min
  let h = 0
  if (d !== 0) {
    if (max === r) h = ((g - b) / d + (g < b ? 6 : 0)) * 60
    else if (max === g) h = ((b - r) / d + 2) * 60
    else h = ((r - g) / d + 4) * 60
  }
  const s = max === 0 ? 0 : d / max
  return { h, s, v: max }
}

export function hsvToRgb(h: number, s: number, v: number): { r: number; g: number; b: number } {
  const c = v * s
  const x = c * (1 - Math.abs(((h / 60) % 2) - 1))
  const m = v - c
  let rp = 0
  let gp = 0
  let bp = 0
  if (h < 60) [rp, gp, bp] = [c, x, 0]
  else if (h < 120) [rp, gp, bp] = [x, c, 0]
  else if (h < 180) [rp, gp, bp] = [0, c, x]
  else if (h < 240) [rp, gp, bp] = [0, x, c]
  else if (h < 300) [rp, gp, bp] = [x, 0, c]
  else [rp, gp, bp] = [c, 0, x]
  return {
    r: (rp + m) * 255,
    g: (gp + m) * 255,
    b: (bp + m) * 255,
  }
}

export function hexToHsv(hex: string): { h: number; s: number; v: number } {
  const rgb = parseHex(hex) || { r: 245, g: 245, b: 245 }
  return rgbToHsv(rgb.r, rgb.g, rgb.b)
}

export function hsvToHex(h: number, s: number, v: number): string {
  const { r, g, b } = hsvToRgb(h, s, v)
  return toHex(r, g, b)
}

export function chatBgCss(bg?: ChatBg | null): string {
  if (!bg || bg.kind === 'default') return 'var(--im-color-chat, #f5f5f5)'
  if (bg.kind === 'color' && bg.hex) {
    const recipe = bg.id ? CHINESE_COLOR_RECIPES.find((c) => c.id === bg.id) : undefined
    // 中国色配方：正色淡化为聊天底；自定义调色盘：直接使用所选色
    if (recipe) return softChatHex(recipe.hex)
    return bg.hex
  }
  if (bg.kind === 'gradient' && bg.id) {
    const preset = CHAT_BG_GRADIENTS.find((g) => g.id === bg.id)
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
      const r = CHINESE_COLOR_RECIPES.find((c) => c.id === bg.id)
      if (r) return r.name
    }
    return bg.hex?.toUpperCase() || '自定义色'
  }
  if (bg.kind === 'gradient') {
    return CHAT_BG_GRADIENTS.find((g) => g.id === bg.id)?.label || '渐变'
  }
  if (bg.kind === 'image') return '自定义图片'
  return '默认'
}
