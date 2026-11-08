// 桌布与 App 图标取自这台 Mac（/System/Library/Desktop Pictures/、各 App 的 AppIcon.icns，sips 转成 PNG）。
// 两台机器各用「自己机器」的桌布，不能互换：
//   Neo  = Mac Blue.heic，MacBook Neo 自己那套彩色桌布（Mac Blue/Pink/Purple/Yellow，
//          随 MacBook Neo 首发，macOS 26.4 才开放给其它 Mac）。见 MacRumors 2026-03-09 / AppleInsider。
//   Air  = Motion Blue.heic，MacBook Air 自己那套桌布（Motion Blue/Green/Purple/Yellow）。
//          注意：苹果内建的那批还有 iMac（7 色）、MacBook Neo（Mac 4 色）、Mac Studio、MacBook Pro 各自一套，
//          所以「Mac 那 4 色」不是 Air 的；Air 的是 Motion。之前 Air 配过 Mac Purple（Neo 的）和
//          TahoeDark（全机种系统默认）都是错的。
//          Air 这台在片中是深色外观，故取 Motion Blue 的 Dark (Still) 那一帧（同一颗 heic 里的第 2 张）。
//          Motion Blue 在系统里只有 356 点缩图 + 描述档（.madesktop 是空壳），
//          6016² 原图由 Apple 的 mobile asset 提供，取法见 handoff/FIXES-draft18.md。
// 人、耳机、车内、桌面是生成的实拍板。
import wall from './assets/wall.jpg';
import wallAir from './assets/wall-air.jpg';
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

export const PLATE = { wall, wallAir, face, desk, deskP, ear };

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
