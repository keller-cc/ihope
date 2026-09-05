import { useEffect, useRef, useState, type MouseEvent, type ReactNode } from 'react'
import { DesktopIcon, MobileIcon } from 'tdesign-icons-react'
import { Button, Collapse, Dialog, DialogPlugin, MessagePlugin, Slider } from 'tdesign-react'
import { api, apiErrorMessage, type ChatBg, type ChatBgImage, type ChatTheme, type User } from '../api'
import zhongguoseIcon from '../assets/zhongguose-icon.svg'
import {
  CHAT_BG_GRADIENTS,
  CHINESE_COLOR_RECIPES,
  THEME_ACCENT_PRESETS,
  THEME_BUBBLE_MINE_PRESETS,
  THEME_BUBBLE_PEER_PRESETS,
  THEME_TEXTURES,
  chatBgStyle,
  chatThemeVars,
  resolveChineseColor,
  resolveGradientPreset,
  softChatHex,
  usesFrameWallpaper,
} from '../lib/chatBg'

type Props = {
  visible: boolean
  value?: ChatTheme | null
  onClose: () => void
  onChanged: (user: User) => void
}

type SectionKey = 'accent' | 'bubble' | 'background' | 'texture' | 'opacity' | 'blur'

const DEFAULT_ACCENT = '#12B7F5'
const DEFAULT_BUBBLE_MINE = '#95EC69'
const DEFAULT_BUBBLE_PEER = '#FFFFFF'

function mergePreview(base: ChatTheme | null | undefined, live: ChatTheme): ChatTheme {
  const out: ChatTheme = { ...(base || {}) }
  if (live.accent !== undefined) out.accent = live.accent
  if (live.bubbleMine !== undefined) out.bubbleMine = live.bubbleMine
  if (live.bubblePeer !== undefined) out.bubblePeer = live.bubblePeer
  if (live.background !== undefined) out.background = live.background
  if (live.texture !== undefined) out.texture = live.texture
  if (live.opacity !== undefined) {
    out.opacity = live.opacity < 0 ? undefined : live.opacity
  }
  if (live.blur !== undefined) {
    out.blur = live.blur < 0 ? undefined : live.blur
  }
  return out
}

function hexEq(a?: string | null, b?: string | null): boolean {
  return (a || '').toUpperCase() === (b || '').toUpperCase()
}

const RESET_ALL: ChatTheme = {
  accent: 'default',
  bubbleMine: 'default',
  bubblePeer: 'default',
  background: { kind: 'default' },
  texture: 'none',
  opacity: -1,
  blur: -1,
}

export function ChatThemeDialog({ visible, value, onClose, onChanged }: Props) {
  const fileRef = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [open, setOpen] = useState<SectionKey[]>(['background'])
  const [live, setLive] = useState<ChatTheme>({})
  const [bgImages, setBgImages] = useState<ChatBgImage[]>([])
  const theme = value || {}
  const preview = mergePreview(theme, live)
  const bg = preview.background || { kind: 'default' as const }

  const loadBgImages = async () => {
    try {
      const res = await api.listMeChatBgImages()
      setBgImages(res.images || [])
    } catch {
      /* keep previous */
    }
  }

  // 仅在打开时重置展开态；value 变化（保存后）不得收拢已展开的面板
  useEffect(() => {
    if (!visible) return
    setLive({})
    setOpen(['background'])
    void loadBgImages()
  }, [visible])

  const patch = async (partial: ChatTheme) => {
    setBusy(true)
    try {
      const u = await api.patchMeChatTheme(partial)
      onChanged(u)
      setLive({})
    } catch (e) {
      MessagePlugin.error(apiErrorMessage(e, '设置失败'))
    } finally {
      setBusy(false)
    }
  }

  const applyBg = (next: ChatBg) => {
    setLive((prev) => ({ ...prev, background: next }))
    void patch({ background: next })
  }

  const removeBgImage = (item: ChatBgImage) => {
    const d = DialogPlugin.confirm({
      header: '删除背景图',
      body: '确定从背景库中删除这张图片？若正在使用，将恢复为默认背景。',
      theme: 'danger',
      confirmBtn: { content: '删除', theme: 'danger' },
      onConfirm: async () => {
        setBusy(true)
        try {
          const u = await api.deleteMeChatBgImage(item.id)
          onChanged(u)
          setLive({})
          await loadBgImages()
          MessagePlugin.success('已删除')
          d.destroy()
        } catch (e) {
          MessagePlugin.error(apiErrorMessage(e, '删除失败'))
        } finally {
          setBusy(false)
        }
      },
    })
  }

  const sectionHeader = (title: ReactNode, onReset: () => void) => (
    <div className="im-theme-collapse-head">
      <span className="im-theme-collapse-head__title">{title}</span>
      <button
        type="button"
        className="im-theme-collapse-head__reset"
        disabled={busy}
        onClick={(e: MouseEvent) => {
          e.stopPropagation()
          onReset()
        }}
      >
        恢复
      </button>
    </div>
  )

  return (
    <Dialog
      visible={visible}
      header="随心调"
      onClose={onClose}
      footer={
        <div className="im-theme-footer">
          <Button
            theme="default"
            variant="outline"
            disabled={busy}
            onClick={() => {
              setLive({})
              void patch(RESET_ALL)
            }}
          >
            恢复默认
          </Button>
          <Button theme="default" onClick={onClose}>
            关闭
          </Button>
        </div>
      }
      width={580}
    >
      <div className="im-theme-pane">
        <ThemePreview theme={preview} />

        <div className="im-theme-pane__body">
          <Collapse
            className="im-theme-collapse"
            borderless
            expandMutex={false}
            value={open}
            onChange={(v) => setOpen((Array.isArray(v) ? v : [v]) as SectionKey[])}
          >
            <Collapse.Panel
              value="accent"
              header={sectionHeader('主题色', () => void patch({ accent: 'default' }))}
            >
              <div className="im-bg-palette im-bg-palette--compact">
                <button
                  type="button"
                  className={!preview.accent ? 'im-bg-chip is-active' : 'im-bg-chip'}
                  style={{
                    background: `linear-gradient(145deg, #5ec8f0, ${DEFAULT_ACCENT})`,
                  }}
                  disabled={busy}
                  title={`默认 ${DEFAULT_ACCENT}`}
                  onClick={() => {
                    setLive((prev) => ({ ...prev, accent: '' }))
                    void patch({ accent: 'default' })
                  }}
                >
                  <span>默认</span>
                </button>
                {THEME_ACCENT_PRESETS.map((c) => {
                  const on = hexEq(preview.accent, c.hex)
                  return (
                    <button
                      key={c.id}
                      type="button"
                      className={on ? 'im-bg-chip is-active' : 'im-bg-chip'}
                      style={{ background: c.hex }}
                      disabled={busy}
                      title={`${c.label} ${c.hex}`}
                      onClick={() => {
                        setLive((prev) => ({ ...prev, accent: c.hex }))
                        void patch({ accent: c.hex })
                      }}
                    >
                      <span>{c.label}</span>
                    </button>
                  )
                })}
              </div>
            </Collapse.Panel>

            <Collapse.Panel
              value="bubble"
              header={sectionHeader('气泡', () =>
                void patch({ bubbleMine: 'default', bubblePeer: 'default' }),
              )}
            >
              <div className="im-bg-section-title">我的</div>
              <div className="im-bg-palette im-bg-palette--compact">
                <button
                  type="button"
                  className={!preview.bubbleMine ? 'im-bg-chip is-active' : 'im-bg-chip'}
                  style={{ background: DEFAULT_BUBBLE_MINE }}
                  disabled={busy}
                  title={`默认 ${DEFAULT_BUBBLE_MINE}`}
                  onClick={() => {
                    setLive((prev) => ({ ...prev, bubbleMine: '' }))
                    void patch({ bubbleMine: 'default' })
                  }}
                >
                  <span>默认</span>
                </button>
                {THEME_BUBBLE_MINE_PRESETS.map((c) => {
                  const on = hexEq(preview.bubbleMine, c.hex)
                  return (
                    <button
                      key={c.id}
                      type="button"
                      className={on ? 'im-bg-chip is-active' : 'im-bg-chip'}
                      style={{ background: c.hex }}
                      disabled={busy}
                      title={`${c.label} ${c.hex}`}
                      onClick={() => {
                        setLive((prev) => ({ ...prev, bubbleMine: c.hex }))
                        void patch({ bubbleMine: c.hex })
                      }}
                    >
                      <span>{c.label}</span>
                    </button>
                  )
                })}
              </div>
              <div className="im-bg-section-title">对方</div>
              <div className="im-bg-palette im-bg-palette--compact">
                <button
                  type="button"
                  className={!preview.bubblePeer ? 'im-bg-chip is-active' : 'im-bg-chip'}
                  style={{ background: DEFAULT_BUBBLE_PEER, border: '1px solid #ddd' }}
                  disabled={busy}
                  title={`默认 ${DEFAULT_BUBBLE_PEER}`}
                  onClick={() => {
                    setLive((prev) => ({ ...prev, bubblePeer: '' }))
                    void patch({ bubblePeer: 'default' })
                  }}
                >
                  <span>默认</span>
                </button>
                {THEME_BUBBLE_PEER_PRESETS.map((c) => {
                  const on = hexEq(preview.bubblePeer, c.hex)
                  return (
                    <button
                      key={c.id}
                      type="button"
                      className={on ? 'im-bg-chip is-active' : 'im-bg-chip'}
                      style={{ background: c.hex }}
                      disabled={busy}
                      title={`${c.label} ${c.hex}`}
                      onClick={() => {
                        setLive((prev) => ({ ...prev, bubblePeer: c.hex }))
                        void patch({ bubblePeer: c.hex })
                      }}
                    >
                      <span>{c.label}</span>
                    </button>
                  )
                })}
              </div>
            </Collapse.Panel>

            <Collapse.Panel
              value="background"
              header={sectionHeader(
                <span className="im-theme-collapse-head__with-link">
                  背景
                  <a
                    className="im-bg-section-link im-bg-section-link--icon"
                    href="https://zhongguose.com/"
                    target="_blank"
                    rel="noopener noreferrer"
                    title="中国色"
                    onClick={(e) => e.stopPropagation()}
                  >
                    <img src={zhongguoseIcon} alt="" width={16} height={16} />
                  </a>
                </span>,
                () => void patch({ background: { kind: 'default' } }),
              )}
            >
              <div className="im-bg-section-title">
                渐变
                <a
                  className="im-bg-section-link"
                  href="https://github.com/ghosh/uiGradients"
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  uiGradients
                </a>
              </div>
              <div className="im-bg-palette">
                <button
                  type="button"
                  className={bg.kind === 'default' ? 'im-bg-chip is-active' : 'im-bg-chip'}
                  style={{
                    background: 'linear-gradient(165deg, #E8E8E8 0%, #F5F5F5 55%, #FAFAFA 100%)',
                  }}
                  disabled={busy}
                  title="默认"
                  onClick={() => applyBg({ kind: 'default' })}
                >
                  <span>默认</span>
                </button>
                {CHAT_BG_GRADIENTS.map((g) => {
                  const on = bg.kind === 'gradient' && resolveGradientPreset(bg.id)?.id === g.id
                  return (
                    <button
                      key={g.id}
                      type="button"
                      className={on ? 'im-bg-chip is-active' : 'im-bg-chip'}
                      style={{ background: g.css }}
                      disabled={busy}
                      title={g.label}
                      onClick={() => applyBg({ kind: 'gradient', id: g.id })}
                    >
                      <span>{g.label}</span>
                    </button>
                  )
                })}
              </div>

              <div className="im-bg-section-title">中国色</div>
              <div className="im-bg-palette">
                {CHINESE_COLOR_RECIPES.map((c) => {
                  const soft = softChatHex(c.hex)
                  const on = bg.kind === 'color' && resolveChineseColor(bg.id)?.id === c.id
                  return (
                    <button
                      key={c.id}
                      type="button"
                      className={on ? 'im-bg-chip is-active' : 'im-bg-chip'}
                      style={{
                        background: `linear-gradient(155deg, ${softChatHex(c.hex, 0.55)} 0%, ${soft} 55%, #FFFFFF 100%)`,
                      }}
                      disabled={busy}
                      title={`${c.name} ${c.hex}`}
                      onClick={() => applyBg({ kind: 'color', id: c.id, hex: c.hex })}
                    >
                      <i className="im-bg-chip__dot" style={{ background: c.hex }} />
                      <span>{c.name}</span>
                    </button>
                  )
                })}
              </div>

              <div className="im-bg-section-title">图片</div>
              <div className="im-bg-actions">
                <Button
                  theme="primary"
                  variant="outline"
                  loading={busy}
                  onClick={() => fileRef.current?.click()}
                >
                  上传图片
                </Button>
                <input
                  ref={fileRef}
                  type="file"
                  accept="image/*"
                  hidden
                  onChange={async (e) => {
                    const file = e.target.files?.[0]
                    e.target.value = ''
                    if (!file) return
                    if (file.size > 10 * 1024 * 1024) {
                      MessagePlugin.warning('图片过大（最大 10MB）')
                      return
                    }
                    setBusy(true)
                    try {
                      const u = await api.uploadMeChatBg(file)
                      onChanged(u)
                      setLive({})
                      await loadBgImages()
                      MessagePlugin.success('已上传')
                    } catch (err) {
                      MessagePlugin.error(apiErrorMessage(err, '上传失败'))
                    } finally {
                      setBusy(false)
                    }
                  }}
                />
              </div>
              {bgImages.length > 0 ? (
                <div className="im-bg-library">
                  {bgImages.map((img) => {
                    const on = bg.kind === 'image' && bg.url === img.url
                    return (
                      <div
                        key={img.id}
                        className={on ? 'im-bg-library__item is-active' : 'im-bg-library__item'}
                      >
                        <button
                          type="button"
                          className="im-bg-library__thumb"
                          style={chatBgStyle({ kind: 'image', url: img.url })}
                          disabled={busy}
                          title="设为背景"
                          onClick={() => applyBg({ kind: 'image', url: img.url })}
                        />
                        <button
                          type="button"
                          className="im-bg-library__del"
                          disabled={busy}
                          title="删除"
                          aria-label="删除背景图"
                          onClick={(e) => {
                            e.stopPropagation()
                            removeBgImage(img)
                          }}
                        >
                          ×
                        </button>
                      </div>
                    )
                  })}
                </div>
              ) : (
                <p className="im-muted im-bg-library__empty">上传后的图片会出现在这里，可随时选用或删除。</p>
              )}
            </Collapse.Panel>

            <Collapse.Panel
              value="texture"
              header={sectionHeader('纹理', () => void patch({ texture: 'none' }))}
            >
              <div className="im-bg-palette im-bg-palette--compact">
                {THEME_TEXTURES.map((t) => {
                  const cur = preview.texture || 'none'
                  const on = cur === t.id
                  const label = t.id === 'none' ? '默认' : t.label
                  return (
                    <button
                      key={t.id}
                      type="button"
                      className={
                        on
                          ? `im-bg-chip im-texture-chip is-active im-texture-chip--${t.id}`
                          : `im-bg-chip im-texture-chip im-texture-chip--${t.id}`
                      }
                      disabled={busy}
                      title={label}
                      onClick={() => {
                        setLive((prev) => ({ ...prev, texture: t.id }))
                        void patch({ texture: t.id })
                      }}
                    >
                      <span>{label}</span>
                    </button>
                  )
                })}
              </div>
            </Collapse.Panel>

            <Collapse.Panel
              value="opacity"
              header={sectionHeader('面板透明度', () => void patch({ opacity: -1 }))}
            >
              <ThemePercentSlider
                value={preview.opacity ?? 1}
                busy={busy}
                isDefault={preview.opacity == null}
                defaultTitle="默认 100%"
                onPreview={(opacity) => setLive((prev) => ({ ...prev, opacity }))}
                onCommit={(opacity) => void patch({ opacity })}
                onResetDefault={() => {
                  setLive((prev) => ({ ...prev, opacity: -1 }))
                  void patch({ opacity: -1 })
                }}
              />
            </Collapse.Panel>

            <Collapse.Panel
              value="blur"
              header={sectionHeader('毛玻璃', () => void patch({ blur: -1 }))}
            >
              <ThemePercentSlider
                value={preview.blur ?? 0.83}
                busy={busy}
                isDefault={preview.blur == null}
                defaultTitle="默认"
                onPreview={(blur) => setLive((prev) => ({ ...prev, blur }))}
                onCommit={(blur) => void patch({ blur })}
                onResetDefault={() => {
                  setLive((prev) => ({ ...prev, blur: -1 }))
                  void patch({ blur: -1 })
                }}
              />
            </Collapse.Panel>
          </Collapse>
        </div>
      </div>
    </Dialog>
  )
}

/** @deprecated use ChatThemeDialog */
export const ChatBackgroundDialog = ChatThemeDialog

function ThemePreview({ theme }: { theme: ChatTheme }) {
  const [device, setDevice] = useState<'pc' | 'mobile'>('pc')
  const [phoneTab, setPhoneTab] = useState<'home' | 'chat' | 'drawer'>('chat')
  const texture = theme.texture && theme.texture !== 'none' ? theme.texture : null
  const accent = theme.accent || 'var(--im-color-primary, #12B7F5)'
  const isMobile = device === 'mobile'
  const frameWallpaper = usesFrameWallpaper(theme)
  const vars = chatThemeVars(theme, { frameWallpaper })

  const renderFrameWallpaper = (opts?: { skipRail?: boolean }) =>
    frameWallpaper ? (
      <div
        className={[
          'im-theme-preview__wallpaper',
          opts?.skipRail ? 'im-theme-preview__wallpaper--skip-rail' : '',
        ]
          .filter(Boolean)
          .join(' ')}
        style={chatBgStyle(theme.background)}
        aria-hidden
      >
        {texture && <div className={`im-messages__texture im-messages__texture--${texture}`} />}
      </div>
    ) : null

  const renderChatStage = () => (
    <div
      className="im-theme-preview__stage"
      style={frameWallpaper ? undefined : chatBgStyle(theme.background)}
    >
      {!frameWallpaper && texture && (
        <div className={`im-messages__texture im-messages__texture--${texture}`} aria-hidden />
      )}
      <div className="im-theme-preview__row">
        <div className="im-theme-preview__avatar" aria-hidden />
        <div className="im-theme-preview__bubble im-theme-preview__bubble--peer">你好呀</div>
      </div>
      <div className="im-theme-preview__row im-theme-preview__row--mine">
        <div className="im-theme-preview__bubble im-theme-preview__bubble--mine">随心调预览</div>
        <div
          className="im-theme-preview__avatar im-theme-preview__avatar--mine"
          style={{ background: accent }}
          aria-hidden
        />
      </div>
    </div>
  )

  const renderTabbar = () => (
    <nav className="im-theme-preview__tabbar" aria-hidden>
      <span className="is-active" style={{ color: accent }}>
        <i className="im-ico im-ico--msg" />
        <em>消息</em>
      </span>
      <span>
        <i className="im-ico im-ico--contacts" />
        <em>联系人</em>
      </span>
    </nav>
  )

  return (
    <div
      className={[
        'im-theme-preview',
        frameWallpaper ? 'im-theme-preview--wallpaper' : '',
        isMobile ? 'im-theme-preview--mobile' : 'im-theme-preview--pc',
      ]
        .filter(Boolean)
        .join(' ')}
      style={vars}
    >
      <div className="im-theme-preview__toolbar">
        <span className="im-theme-preview__toolbar-label">预览</span>
        <div className="im-theme-preview__device" role="group" aria-label="预览设备">
          <button
            type="button"
            className={!isMobile ? 'is-active' : undefined}
            title="电脑"
            aria-label="电脑预览"
            aria-pressed={!isMobile}
            onClick={() => setDevice('pc')}
          >
            <DesktopIcon size="18px" />
          </button>
          <button
            type="button"
            className={isMobile ? 'is-active' : undefined}
            title="手机"
            aria-label="手机预览"
            aria-pressed={isMobile}
            onClick={() => setDevice('mobile')}
          >
            <MobileIcon size="18px" />
          </button>
        </div>
      </div>

      <div className="im-theme-preview__shell" style={{ background: 'var(--im-color-bg)' }}>
        {!isMobile ? (
          <div className="im-theme-preview__frame">
            {renderFrameWallpaper({ skipRail: true })}
            <aside className="im-theme-preview__rail" aria-hidden>
              <i className="im-theme-preview__rail-dot" />
              <span className="im-theme-preview__rail-item is-active" style={{ color: accent }}>
                <i className="im-ico im-ico--msg" />
              </span>
              <span className="im-theme-preview__rail-item">
                <i className="im-ico im-ico--contacts" />
              </span>
              <span className="im-theme-preview__rail-item">
                <i className="im-ico im-ico--set" />
              </span>
            </aside>

            <div className="im-theme-preview__sidebar">
              <div className="im-theme-preview__side-head">消息</div>
              <div className="im-theme-preview__side-item is-active">
                <i className="im-theme-preview__avatar im-theme-preview__avatar--sm" />
                <div className="im-theme-preview__side-meta">
                  <strong>好友</strong>
                  <em>你好呀</em>
                </div>
              </div>
              <div className="im-theme-preview__side-item">
                <i className="im-theme-preview__avatar im-theme-preview__avatar--sm" />
                <div className="im-theme-preview__side-meta">
                  <strong>群聊</strong>
                  <em>随心调预览</em>
                </div>
              </div>
            </div>

            <div className="im-theme-preview__chat">
              <div className="im-theme-preview__chat-head">好友</div>
              {renderChatStage()}
              <div className="im-theme-preview__composer">
                <span>输入消息…</span>
                <em className="im-theme-preview__send">发送</em>
              </div>
            </div>
          </div>
        ) : (
          <div className="im-theme-preview__phones">
            <div className="im-theme-preview__phone-tabs" role="tablist" aria-label="手机预览页">
              {(
                [
                  ['home', '首页'],
                  ['chat', '会话'],
                  ['drawer', '抽屉'],
                ] as const
              ).map(([id, label]) => (
                <button
                  key={id}
                  type="button"
                  role="tab"
                  aria-selected={phoneTab === id}
                  className={phoneTab === id ? 'is-active' : undefined}
                  onClick={() => setPhoneTab(id)}
                >
                  {label}
                </button>
              ))}
            </div>
            <div className="im-theme-preview__phone">
              <div className="im-theme-preview__frame im-theme-preview__frame--phone">
                {renderFrameWallpaper()}
                {phoneTab === 'home' && (
                  <>
                    <div className="im-theme-preview__home">
                      <div className="im-theme-preview__home-head">
                        <i
                          className="im-theme-preview__avatar im-theme-preview__avatar--sm"
                          style={{ background: accent }}
                        />
                        <strong>消息</strong>
                        <em>+</em>
                      </div>
                      <div className="im-theme-preview__side-item is-active">
                        <i className="im-theme-preview__avatar im-theme-preview__avatar--sm" />
                        <div className="im-theme-preview__side-meta">
                          <strong>好友</strong>
                          <em>你好呀</em>
                        </div>
                      </div>
                      <div className="im-theme-preview__side-item">
                        <i className="im-theme-preview__avatar im-theme-preview__avatar--sm" />
                        <div className="im-theme-preview__side-meta">
                          <strong>群聊</strong>
                          <em>随心调预览</em>
                        </div>
                      </div>
                    </div>
                    {renderTabbar()}
                  </>
                )}
                {phoneTab === 'chat' && (
                  <div className="im-theme-preview__chat">
                    <div className="im-theme-preview__chat-head">好友</div>
                    {renderChatStage()}
                    <div className="im-theme-preview__composer">
                      <span>输入消息…</span>
                      <em className="im-theme-preview__send">发送</em>
                    </div>
                  </div>
                )}
                {phoneTab === 'drawer' && (
                  <>
                    <div className="im-theme-preview__home im-theme-preview__home--dim">
                      <div className="im-theme-preview__home-head">
                        <i className="im-theme-preview__avatar im-theme-preview__avatar--sm" />
                        <strong>消息</strong>
                      </div>
                      <div className="im-theme-preview__side-item">
                        <i className="im-theme-preview__avatar im-theme-preview__avatar--sm" />
                        <div className="im-theme-preview__side-meta">
                          <strong>好友</strong>
                          <em>你好呀</em>
                        </div>
                      </div>
                    </div>
                    {renderTabbar()}
                    <aside className="im-theme-preview__drawer" aria-hidden>
                      <div className="im-theme-preview__drawer-hero">
                        <i
                          className="im-theme-preview__avatar"
                          style={{ background: accent, width: 28, height: 28, borderRadius: '50%' }}
                        />
                        <div>
                          <strong>我</strong>
                          <em>IHope 号</em>
                        </div>
                      </div>
                      <div className="im-theme-preview__drawer-row">设置</div>
                      <div className="im-theme-preview__drawer-row">随心调</div>
                      <div className="im-theme-preview__drawer-row">退出登录</div>
                    </aside>
                  </>
                )}
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function ThemePercentSlider({
  value,
  busy,
  isDefault,
  defaultTitle = '默认',
  onPreview,
  onCommit,
  onResetDefault,
}: {
  value: number
  busy: boolean
  isDefault: boolean
  defaultTitle?: string
  onPreview?: (v: number) => void
  onCommit: (v: number) => void
  onResetDefault: () => void
}) {
  const [local, setLocal] = useState(() => Math.round(value * 100))
  useEffect(() => {
    setLocal(Math.round(value * 100))
  }, [value])
  return (
    <div className="im-theme-opacity">
      <button
        type="button"
        className={isDefault ? 'im-bg-chip is-active' : 'im-bg-chip'}
        style={{
          background: 'linear-gradient(165deg, #E8E8E8 0%, #F5F5F5 55%, #FAFAFA 100%)',
          minWidth: 56,
        }}
        disabled={busy}
        title={defaultTitle}
        onClick={onResetDefault}
      >
        <span>默认</span>
      </button>
      <Slider
        min={0}
        max={100}
        value={local}
        disabled={busy}
        onChange={(v) => {
          const n = Number(Array.isArray(v) ? v[0] : v)
          setLocal(n)
          onPreview?.(n / 100)
        }}
        onChangeEnd={(v) => {
          const n = Number(Array.isArray(v) ? v[0] : v)
          onCommit(n / 100)
        }}
      />
      <span className="im-theme-opacity__val">{local}%</span>
    </div>
  )
}
