package;

#if android
import android.Tools;
import android.Permissions;
import android.PermissionsList;
#end
import lime.app.Application;
import lime.system.System as LimeSystem;
import openfl.events.UncaughtErrorEvent;
import openfl.utils.Assets as OpenFlAssets;
import openfl.Lib;
import haxe.CallStack.StackItem;
import haxe.CallStack;
import haxe.io.Path;
#if ios
import haxe.io.Bytes;
#end
import sys.FileSystem;
import sys.io.File;
import flash.system.System;
import flixel.FlxG;

/**
 * ...
 * @author: Saw (M.A. Jigsaw)
 */

using StringTools;

class SUtil
{
	public static var errMsg:String;
	public static function getPath():String
	{
		#if android
        return Tools.getExternalStorageDirectory() + '/' + '.' + Application.current.meta.get('file') + '/';
		#end

		#if ios
		return LimeSystem.documentsDirectory;
		#end

		#if windows
		return '';
		#end
	}

	// ==================== [PE-iOS] 首次启动自动释放内置资源 ====================
	// 只在「全新安装」（Documents 下 assets 和 mods 都不存在）时，把 App 包里自带的
	// resources.zip 解开，用户装完 IPA 直接就能玩，不用手动解压。
	//
	// 两条铁律（都是踩过的坑）：
	//   1) 只缺一个文件夹时**绝不重新解压**，只补一个空文件夹。
	//      * 否则用户把 mods 改名做「禁用模组」测试，引擎立刻又把 mods 重建回来，测试白做；
	//      * 更糟的是会把用户自己放进去的 assets 一并覆盖成内置占位版。
	//   2) 解压时遇到已存在的文件一律跳过，绝不覆盖用户文件。
	#if ios
	public static function ensureAssets():Void
	{
		var base:String = getPath();
		if (base == null || base.length < 1) return;

		var hasAssets:Bool = FileSystem.exists(base + 'assets');
		var hasMods:Bool = FileSystem.exists(base + 'mods');

		if (hasAssets && hasMods)
			return; // 已经装好了，什么都不做

		if (!hasAssets && !hasMods)
		{
			// 全新安装：找 App 包里的内置 resources.zip
			var bytes:Bytes = null;
			for (id in ['assets/resources.zip', 'resources.zip', 'assets/preload/resources.zip'])
			{
				try { bytes = OpenFlAssets.getBytes(id); } catch (e:Dynamic) { bytes = null; }
				if (bytes != null && bytes.length > 16)
				{
					trace('[PE-iOS] 找到内置资源包: ' + id + ' (' + bytes.length + ' bytes)');
					break;
				}
				bytes = null;
			}

			if (bytes != null && bytes.length > 16)
			{
				trace('[PE-iOS] 全新安装：正在释放内置资源到 ' + base + ' ...');
				var count:Int = unzipInto(bytes, base);
				trace('[PE-iOS] 资源释放完成，共 ' + count + ' 个文件');
			}
			else
			{
				trace('[PE-iOS] 没有内置 resources.zip，跳过自动释放（将使用旧的手动解压方式）');
			}
		}
		else
		{
			// 只缺一侧：说明是已有安装（用户手动删/改过），只补空目录，绝不重新解压
			trace('[PE-iOS] 只缺一侧文件夹，仅补空目录，不重新解压（保护用户数据）');
		}

		if (!FileSystem.exists(base + 'mods'))
		{
			try { FileSystem.createDirectory(base + 'mods'); } catch (e:Dynamic) {}
		}
		if (!FileSystem.exists(base + 'assets'))
		{
			try { FileSystem.createDirectory(base + 'assets'); } catch (e:Dynamic) {}
		}
	}

	static function unzipInto(bytes:Bytes, destDir:String):Int
	{
		var count:Int = 0;
		// haxe.zip.Reader.read() 返回的是 haxe.ds.List<Entry>（Haxe 4.2 / 4.3 都一样），
		// 不能直接赋给 Array，否则报：List<Entry> should be Array<Entry>。
		// 这里用数组推导转一遍，两个 Haxe 版本都能编译。
		var entries:Array<haxe.zip.Entry> = [];
		try
		{
			entries = [for (e in new haxe.zip.Reader(new haxe.io.BytesInput(bytes)).read()) e];
		}
		catch (e:Dynamic)
		{
			trace('[PE-iOS] 解压失败（不是合法 zip？）: ' + e);
			return 0;
		}

		for (entry in entries)
		{
			if (entry == null || entry.fileName == null) continue;
			var name:String = entry.fileName.split('\\').join('/');
			if (name.length < 1 || name.charAt(name.length - 1) == '/') continue; // 目录项跳过

			// Reader 读出来的是「压缩状态」的数据，要用 haxe.zip.Tools.uncompress(entry) 解压。
			// 注意：它的参数是整个 Entry（原地解压并把结果写回 entry.data），不是 Bytes。
			if (entry.compressed)
			{
				try { haxe.zip.Tools.uncompress(entry); }
				catch (e:Dynamic)
				{
					trace('[PE-iOS] 解压条目失败 ' + name + ': ' + e);
					continue;
				}
			}

			var data:Bytes = entry.data;
			if (data == null) continue;

			var out:String = destDir + name;
			if (FileSystem.exists(out)) continue; // 已存在就不覆盖（保护用户文件）

			var slash:Int = out.lastIndexOf('/');
			if (slash > 0) mkdirs(out.substring(0, slash));

			try
			{
				File.saveBytes(out, data);
				count++;
			}
			catch (e:Dynamic)
			{
				trace('[PE-iOS] 写入失败 ' + out + ': ' + e);
			}
		}
		return count;
	}

	static function mkdirs(dir:String):Void
	{
		if (dir == null || dir.length < 2 || FileSystem.exists(dir)) return;
		var slash:Int = dir.lastIndexOf('/');
		if (slash > 1) mkdirs(dir.substring(0, slash));
		try { FileSystem.createDirectory(dir); } catch (e:Dynamic) {}
	}
	#end
	// =====================================================================

	public static function doTheCheck()
	{
		#if ios
		// 先把内置资源释放出来，再去检查目录在不在
		ensureAssets();
		#end

		if (!FileSystem.exists(SUtil.getPath() + 'assets') && !FileSystem.exists(SUtil.getPath() + 'mods'))
			{
				SUtil.applicationAlert('Uncaught Error :(!', "Whoops, seems you didn't extract the files from the Assets .zip!\nPlease watch the tutorial by pressing OK.");
				CoolUtil.browserLoad('https://youtu.be/zjvkTmdWvfU');
				System.exit(0);
			}
			else
			{
				if (!FileSystem.exists(SUtil.getPath() + 'assets'))
				{
					SUtil.applicationAlert('Uncaught Error :(!', "Whoops, seems you didn't extract the assets folder from the Assets .zip!\nPlease watch the tutorial by pressing OK.");
					CoolUtil.browserLoad('https://youtu.be/zjvkTmdWvfU');
					System.exit(0);
				}

				if (!FileSystem.exists(SUtil.getPath() + 'mods'))
				{
					SUtil.applicationAlert('Uncaught Error :(!', "Whoops, seems you didn't extract the mods folder from the Assets .zip!\nPlease watch the tutorial by pressing OK.");
					CoolUtil.browserLoad('https://youtu.be/zjvkTmdWvfU');
					System.exit(0);
				}
			}
	}

	public static function gameCrashCheck()
	{
		Lib.current.loaderInfo.uncaughtErrorEvents.addEventListener(UncaughtErrorEvent.UNCAUGHT_ERROR, onCrash);
	}

	public static function onCrash(e:UncaughtErrorEvent):Void
	{
		var callStack:Array<StackItem> = CallStack.exceptionStack(true);
		var dateNow:String = Date.now().toString();
		dateNow = StringTools.replace(dateNow, " ", "_");
		dateNow = StringTools.replace(dateNow, ":", "'");

		var path:String = "crash/" + "crash_" + dateNow + ".txt";
		var errMsg:String = "";

		for (stackItem in callStack)
		{
			switch (stackItem)
			{
				case FilePos(s, file, line, column):
					errMsg += file + " (line " + line + ")\n";
				default:
					Sys.println(stackItem);
			}
		}

		errMsg += e.error;

		if (!FileSystem.exists(SUtil.getPath() + "crash"))
		FileSystem.createDirectory(SUtil.getPath() + "crash");

		File.saveContent(SUtil.getPath() + path, errMsg + "\n");

		Sys.println(errMsg);
		Sys.println("Crash dump saved in " + Path.normalize(path));
		Sys.println("Making a simple alert ...");

		FlxG.switchState(new CrashState());
	}

	private static function applicationAlert(title:String, description:String)
	{
		Application.current.window.alert(description, title);
	}

	#if mobile
	public static function saveContent(fileName:String = 'file', fileExtension:String = '.json', fileData:String = 'you forgot something to add in your code')
	{
		if (!FileSystem.exists(SUtil.getPath() + 'saves'))
			FileSystem.createDirectory(SUtil.getPath() + 'saves');

		File.saveContent(SUtil.getPath() + 'saves/' + fileName + fileExtension, fileData);
		SUtil.applicationAlert('Done :)!', 'File Saved Successfully!');
	}

	public static function saveClipboard(fileData:String = 'you forgot something to add in your code')
	{
		openfl.system.System.setClipboard(fileData);
		SUtil.applicationAlert('Finished!', 'Data Saved to Clipboard Successfully!');
	}

	public static function copyContent(copyPath:String, savePath:String)
	{
		if (!FileSystem.exists(savePath))
			File.saveBytes(savePath, OpenFlAssets.getBytes(copyPath));
	}
	#end
}
