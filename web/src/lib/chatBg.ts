import type { CSSProperties } from 'react'
import type { ChatBg } from '../api'

export type ChatBgPreset = {
  id: string
  label: string
  css: string
}

/** QQ-like soft pastel gradients for chat wallpaper. */
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

export function chatBgStyle(bg?: ChatBg | null): CSSProperties {
  if (!bg || bg.kind === 'default') {
    return { background: 'var(--im-color-chat, #f5f5f5)' }
  }
  if (bg.kind === 'gradient' && bg.id) {
    const preset = CHAT_BG_GRADIENTS.find((g) => g.id === bg.id)
    if (preset) return { background: preset.css }
  }
  if (bg.kind === 'image' && bg.url) {
    return {
      backgroundColor: '#e8e8e8',
      backgroundImage: `url(${bg.url})`,
      backgroundSize: 'cover',
      backgroundPosition: 'center',
      backgroundRepeat: 'no-repeat',
    }
  }
  return { background: 'var(--im-color-chat, #f5f5f5)' }
}

export function chatBgSummary(bg?: ChatBg | null): string {
  if (!bg || bg.kind === 'default') return '默认'
  if (bg.kind === 'gradient') {
    return CHAT_BG_GRADIENTS.find((g) => g.id === bg.id)?.label || '渐变'
  }
  if (bg.kind === 'image') return '自定义图片'
  return '默认'
}
