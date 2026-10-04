// 桌布与 App 图标取自这台 Mac（/System/Library/Desktop Pictures/Mac Blue.heic、各 App 的 AppIcon.icns，sips 转成 PNG）。
// 人、耳机、车内、桌面是生成的实拍板。
import wall from './assets/wall.jpg';
import face from './assets/face.jpg';
import desk from './assets/desk.jpg';
import deskP from './assets/desk_p.jpg';
import ear from './assets/airpods.jpg';

import appstore from './assets/icons/appstore.png';
import calculator from './assets/icons/calculator.png';
import calendar from './assets/icons/calendar.png';
import chatgpt from './assets/icons/chatgpt.png';
import claude from './assets/icons/claude.png';
import clock from './assets/icons/clock.png';
import contacts from './assets/icons/contacts.png';
import cursor from './assets/icons/cursor.png';
import discord from './assets/icons/discord.png';
import facetime from './assets/icons/facetime.png';
import finalcutpro from './assets/icons/finalcutpro.png';
import finder from './assets/icons/finder.png';
import findmy from './assets/icons/findmy.png';
import freeform from './assets/icons/freeform.png';
import games from './assets/icons/games.png';
import googlechrome from './assets/icons/googlechrome.png';
import home from './assets/icons/home.png';
import iphonemirroring from './assets/icons/iphonemirroring.png';
import journal from './assets/icons/journal.png';
import logicpro from './assets/icons/logicpro.png';
import mail from './assets/icons/mail.png';
import maps from './assets/icons/maps.png';
import messages from './assets/icons/messages.png';
import music from './assets/icons/music.png';
import news from './assets/icons/news.png';
import notes from './assets/icons/notes.png';
import passwords from './assets/icons/passwords.png';
import photobooth from './assets/icons/photobooth.png';
import photos from './assets/icons/photos.png';
import podcasts from './assets/icons/podcasts.png';
import preview from './assets/icons/preview.png';
import reminders from './assets/icons/reminders.png';
import safari from './assets/icons/safari.png';
import shortcuts from './assets/icons/shortcuts.png';
import stocks from './assets/icons/stocks.png';
import systemsettings from './assets/icons/systemsettings.png';
import tips from './assets/icons/tips.png';
import tv from './assets/icons/tv.png';
import voicememos from './assets/icons/voicememos.png';
import weather from './assets/icons/weather.png';
import wechat from './assets/icons/wechat.png';
import xcode from './assets/icons/xcode.png';

export const PLATE = { wall, face, desk, deskP, ear };

export const ICON = {
  appstore, calculator, calendar, chatgpt, claude, clock, contacts, cursor, discord, facetime, finalcutpro, finder, findmy,
  freeform, games, googlechrome, home, iphonemirroring, journal, logicpro, mail, maps, messages, music, news, notes,
  passwords, photobooth, photos, podcasts, preview, reminders, safari, shortcuts, stocks, systemsettings, tips, tv,
  voicememos, weather, wechat, xcode,
};
export type IconName = keyof typeof ICON;

/** 启动台第一页：系统里的中文名。 */
export const LAUNCH: [IconName, string][] = [
  ['safari', 'Safari 浏览器'], ['mail', '邮件'], ['messages', '信息'], ['maps', '地图'], ['photos', '照片'], ['facetime', 'FaceTime 通话'], ['calendar', '日历'],
  ['contacts', '通讯录'], ['reminders', '提醒事项'], ['notes', '备忘录'], ['freeform', '无边记'], ['tv', 'TV'], ['music', '音乐'], ['podcasts', '播客'],
  ['news', '新闻'], ['appstore', 'App Store'], ['systemsettings', '系统设置'], ['weather', '天气'], ['clock', '时钟'], ['stocks', '股市'], ['home', '家庭'],
  ['shortcuts', '快捷指令'], ['journal', '手记'], ['passwords', '密码'], ['findmy', '查找'], ['preview', '预览'], ['photobooth', 'Photo Booth'], ['games', '游戏'],
  ['claude', 'Claude'], ['chatgpt', 'ChatGPT'], ['cursor', 'Cursor'], ['xcode', 'Xcode'], ['finalcutpro', 'Final Cut Pro'], ['logicpro', 'Logic Pro'], ['wechat', '微信'],
];

export const DOCK: IconName[] = ['finder', 'safari', 'messages', 'mail', 'maps', 'photos', 'facetime', 'calendar', 'notes', 'music', 'appstore', 'claude', 'cursor', 'systemsettings'];
