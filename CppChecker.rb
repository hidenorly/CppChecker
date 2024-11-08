#!/usr/bin/env ruby

# Copyright 2022, 2023, 2024 hidenory
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

require 'fileutils'
require 'optparse'
require 'rexml/document'
require_relative 'FileUtil'
require_relative 'StrUtil'
require_relative 'TaskManager'
require_relative 'ExecUtil'
require_relative 'Reporter'

class RepoUtil
	DEF_MANIFESTFILE = "manifest.xml"
	DEF_MANIFESTFILE_DIRS = [
		"/.repo/",
		"/.repo/manifests/"
	]

	def self.getAvailableManifestPath(basePath, manifestFilename)
		DEF_MANIFESTFILE_DIRS.each do |aDir|
			path = basePath + aDir.to_s + manifestFilename
			if FileTest.exist?(path) then
				return path
			end
		end
		return nil
	end

	def self.getPathesFromManifestSub(basePath, manifestFilename, pathGitPath, pathFilter, groupFilter)
		manifestPath = getAvailableManifestPath(basePath, manifestFilename)
		if manifestPath && FileTest.exist?(manifestPath) then
			doc = REXML::Document.new(open(manifestPath))
			doc.elements.each("manifest/include[@name]") do |anElement|
				getPathesFromManifestSub(basePath, anElement.attributes["name"], pathGitPath, pathFilter, groupFilter)
			end
			doc.elements.each("manifest/project[@path]") do |anElement|
				thePath = anElement.attributes["path"].to_s
				theGitPath = anElement.attributes["name"].to_s
				if pathFilter.empty? || ( !pathFilter.to_s.empty? && thePath.match( pathFilter.to_s ) ) then
					theGroups = anElement.attributes["groups"].to_s
					if theGroups.empty? || groupFilter.empty? || ( !groupFilter.to_s.empty? && theGroups.match( groupFilter.to_s ) ) then
						pathGitPath[thePath] = theGitPath
					end
				end
			end
		end
	end

	def self.getPathesFromManifest(basePath, pathFilter="", groupFilter="")
		pathGitPath = {}

		getPathesFromManifestSub(basePath, DEF_MANIFESTFILE, pathGitPath, pathFilter, groupFilter)

		pathes = []
		pathGitPath.keys.each do |aPath|
			pathes << "#{basePath}/#{aPath}"
		end

		return pathes, pathGitPath
	end
end

class AndroidUtil
	DEF_ANDROID_ROOT=[
	    "/system/",
	    "/frameworks/",
	    "/device/",
	    "/vendor/",
	    "/packages/",
	    "/external/",
	    "/hardware/",
	    "/build/",
	    "/compatibility/",
	    "/bootable/",
	    "/bootloader/",
	    "/bionic/",
	    "/art/",
	    "/dalvik/",
	    "/cts/",
	    "/developers/",
	    "/development/",
	    "/kernel/",
	    "/libnativehelper/",
	    "/pdk/",
	    "/sdk/",
	    "/prebuilts/",
	    "/platform_testing/",
	    "/test/",
	    "/toolchain/",
	    "/tools/"
	]

	def self.getAndroidRootPath(path)
		result = ""
		DEF_ANDROID_ROOT.each do |aPath|
			pos = path.index(aPath)
			if pos then
				result = path.slice(0, pos)
				break
			end
		end
		return result
	end
end


class CppChecker
	DEF_CPPCHECK = "cppcheck"
	DEF_CPPCHECK_TEMPLATE = "[{file}],[{line}],[{severity}],[{id}],[{message}]"
	DEF_EXEC_TIMEOUT = 60*3

	def initialize(targetPath, optEnable, ignoreFiles, timeOut=DEF_EXEC_TIMEOUT, maxThreads = 1)
		@targetPath = File.expand_path(targetPath)
		@optEnable = optEnable
		@ignoreFiles = ignoreFiles
		@timeOut = timeOut
		@maxThreads = maxThreads
	end

	def _parseResult(aLine)
		result = {}

		_result = aLine.split("],[")
		if _result.length >= 5 then
			filename = _result[0].slice(1, _result[0].length)
			if !StrUtil.matches?(filename, @ignoreFiles) then
				found = true
				result["filename"] = filename
				result["line"] = _result[1]
				result["severity"] = _result[2]
				result["id"] = _result[3]
				_result.shift(4)
				_result = _result.join("],[")
				result["message"] = _result.slice(0, _result.length-1)
			end
		end
		return result
	end

	def _filterFiles(files)
		results = []
		files.each do |aFile|
			results << aFile if aFile.end_with?(".cpp") || aFile.end_with?(".c") || aFile.end_with?(".cc") || aFile.end_with?(".h") || aFile.end_with?(".hpp") || aFile.end_with?(".cxx") || aFile.end_with?(".")
		end
		return results
	end

	def getConcurrentNum(numOfFiles)
		result = 0
		numOfFiles = numOfFiles.to_i
		result = ( Math.log(numOfFiles) + 0.9 ).to_i if numOfFiles!=0
		result = 2 if result == 0
		result = [result, @maxThreads].min
		return result
	end

	def execute(targetFiles=["."])
		results = []

		targetFiles = _filterFiles(targetFiles)

		if !targetFiles.empty? then
			exec_cmd = "#{DEF_CPPCHECK} --quiet -j #{getConcurrentNum(targetFiles.length)} --template=\"#{DEF_CPPCHECK_TEMPLATE}\""
			exec_cmd = exec_cmd + " --enable=#{@optEnable}" if @optEnable && !@optEnable.empty?
			exec_cmd = exec_cmd + " #{targetFiles.join(" ")}"

			resultLines = ExecUtil.getExecResultEachLineWithTimeout(exec_cmd, @targetPath, @timeOut, true, true)

			resultLines.each do |aLine|
				_result = _parseResult(aLine)
				results << _result if !_result.empty?
			end
		end

		return results
	end
end


class GitUtil
	def self.isGitDirectory(gitPath)
		return File.directory?("#{gitPath}/.git")
	end

	def self.ensureSha1(sha1)
		sha= sha1.to_s.match(/[0-9a-f]{5,40}/)
		return sha ? sha[0] : nil
	end

	def self.ensureShas(shas)
		result = []
		shas.each do | aSha |
			result << ensureSha1(aSha)
		end

		return result
	end

	def self.getLogNumStatBySha1(gitPath, commitId)
		exec_cmd = "git log --numstat --pretty=\"\" #{commitId}"
		exec_cmd += " 2>/dev/null"

		return ExecUtil.getExecResultEachLine(exec_cmd, gitPath)
	end

	def self.getHeadCommitId(gitPath)
		exec_cmd = "git log --pretty=\"%H\" HEAD -1"
		results = ExecUtil.getExecResultEachLine(exec_cmd, gitPath, false, true)
		return !results.empty? ? results[0] : nil
	end

	def self.getTailCommitId(gitPath)
		return _getTailCommits( gitPath, 1 ).to_s
	end

	def self._getTailCommits(gitPath, count = 1)
		result = nil
		exec_cmd = "git rev-list HEAD | tail -n #{count}"
		exec_cmd += " 2>/dev/null"

		result = ExecUtil.getExecResultEachLine(exec_cmd, gitPath)
		return ensureShas(result)
	end

	def self.getActualTailCommitId(gitPath)
		result = nil
		candidate = _getTailCommits( gitPath, 2 )
		candidate.reverse_each do | aCommitId |
			numStatResult = getLogNumStatBySha1( gitPath, aCommitId )
			if !numStatResult.empty? then
				result = aCommitId
				break
			end
		end
		return result
	end

	def self.getFilesWithGitOpts(gitPath, gitOpt = "", existingFileOnly = true)
		exec_cmd = "git log --name-only --pretty=\"\" #{gitOpt ? gitOpt : ""} | sort -u"
		result = ExecUtil.getExecResultEachLine(exec_cmd, gitPath, false, true, true)
		if existingFileOnly then
			_result = []
			result.each do |aFile|
				_result << aFile if File.exist?("#{gitPath}/#{aFile}")
			end
			result = _result
		end
		return result
	end

	def self._getValue(aLine, key)
		result = nil
		aLine = aLine.to_s
		pos = aLine.index(key)
		if pos then
			result = aLine.slice( pos+key.length, aLine.length )
			result.strip!
		end
		return result
	end

	def self._getValueFromLines(lines, key)
		lines.each do |aLine|
			result = _getValue(aLine, key)
			return result if result
		end
		return ""
	end

	def self.gitBlame(gitPath, filename, line)
		results = {}
		exec_cmd = "git blame -p #{filename} -L #{line},#{line}"
		result = ExecUtil.getExecResultEachLine(exec_cmd, gitPath, false, true, true)
		if !result.empty? then
			results[:commitId] = result[0].split(" ")[0]
			results[:author] = _getValueFromLines(result, "author")
			results[:authorMail] = _getValueFromLines(result, "author-mail")
			results[:theLine] = result.last.to_s.strip
		end
		return results
	end
end


class CppCheckExecutor < TaskAsync
	def initialize(resultCollector, path, options)
		super("CppCheckExecutor #{path}")
		@resultCollector = resultCollector
		@path = path.to_s
		@options = options
		@cppCheck = CppChecker.new( path, options[:optEnable], options[:ignoreFiles], options[:execTimeOut].to_i, options[:numOfThreads].to_i )
	end

	def enhanceResult(results, ignoreInitialCommit = false)
		_results = []
		ignoreCommits = @options[:ignoreCommits]
		ignoreCommits <<  GitUtil.getActualTailCommitId( @path ) if ignoreInitialCommit

		results.each do | aResult |
			theResult = {}
			theResult = GitUtil.gitBlame( @path, aResult["filename"], aResult["line"] ) if !aResult["filename"].empty? && aResult["filename"]!="nofile" && !aResult["line"].empty?
			if theResult.empty? then
				_results << aResult
			else
				if !ignoreCommits.include?( theResult[:commitId] ) then
					_results << aResult.merge( theResult )
				end
			end
		end

		return _results
	end

	def execute
		results = {}
		isGitDirectory = GitUtil.isGitDirectory(@path)
		results[:name] = FileUtil.getFilenameFromPath(@path)
		results[:path] = @path.slice( AndroidUtil.getAndroidRootPath(@path).to_s.length, @path.length )
		results[:fullPath] = @path
		results[:results] = @cppCheck.execute( isGitDirectory ? @options[:gitOpt] ? GitUtil.getFilesWithGitOpts( @path, @options[:gitOpt] ) : ["."] : ["."] )
		results[:results] = enhanceResult( results[:results], @options[:ignoreInitialCommit] ) if isGitDirectory && (!@options[:detailSection] || @options[:detailSection].include?("commitId") || @options[:detailSection].include?("author") || @options[:detailSection].include?("authorMail"))
		@resultCollector.onResult(@path, results) if @resultCollector && !results[:results].empty?
		_doneTask()
	end
end

class CodeWebHelper
	def self.getCodeLink( baseUrl, gitPath, sha1, filename, line )
		return "[#{line}](#{baseUrl}/#{gitPath}/+/#{sha1}/#{filename}\##{line})"
	end

	def self.getRobustGitPath(pathGitPaths, theModulePath)
		result = nil
		result = pathGitPaths[theModulePath] if pathGitPaths.has_key?(theModulePath)
		if !result then
			pathGitPaths.each do |path, gitPath|
				if path.include?(theModulePath) then
					result = gitPath
					break
				end
			end
		end
		return result
	end
end


#---- main --------------------------
options = {
	:verbose => false,
	:reportOutPath => nil,
	:mode => "all",
	:gitOpt => nil,
	:exceptFiles => "test",
	:summarySection => "moduleName|path|error|warning|performance|style|information",
	:enableLinkInSummary => false,
	:codeLink => nil,
	:filterAuthorMatch => nil,
	:detailSection => nil,
	:optEnable => nil, # subset of "warning,style,performance,portability,information,unusedFunction,missingInclude" or "all"
	:pathFilter => nil,
	:ignoreFiles => [],
	:ignoreInitialCommit => false,
	:ignoreCommits => [],
	:surpressNonIssue => false,
	:execTimeOut => 5*60,
	:numOfThreads => TaskManagerAsync.getNumberOfProcessor()
}

reporter = MarkdownReporter
resultCollector = ResultCollectorHash.new()

opt_parser = OptionParser.new do |opts|
	opts.banner = "Usage: usage ANDROID_HOME"

	opts.on("-m", "--mode=", "Specify report mode all or summary or detail default:#{options[:mode]}") do |mode|
		mode = mode.to_s.downcase
		case mode
		when "summary"
			options[:mode] = "summary"
		when "all"
			options[:mode] = "all"
		when "detail"
			options[:mode] = "detail"
		end
	end

	opts.on("-p", "--reportOutPath=", "Specify report output folder if you want to report out as file") do |reportOutPath|
		options[:reportOutPath] = reportOutPath
	end

	opts.on("-r", "--reportFormat=", "Specify report format markdown|csv|xml (default:markdown)") do |reportFormat|
		case reportFormat.to_s.downcase
		when "markdown"
			reporter = MarkdownReporter
		when "csv"
			reporter = CsvReporter
		when "xml"
			reporter = XmlReporter
		end
	end

	opts.on("-g", "--gitOpt=", "Specify option for git (default:#{options[:gitOpt]})") do |gitOpt|
		options[:gitOpt] = gitOpt
	end

	opts.on("-e", "--optEnable=", "Specify option --enable for cppcheck (default:#{options[:optEnable]})") do |optEnable|
		options[:optEnable] = optEnable
	end

	opts.on("", "--summarySection=", "Specify summary sections with | separator (default:#{options[:summarySection]})(\"\" means everything)") do |summarySection|
		options[:summarySection] = summarySection
	end

	opts.on("", "--detailSection=", "Specify detail sections with | separator (default:#{options[:detailSection]})(\"\" means everything)") do |detailSection|
		options[:detailSection] = detailSection
	end

	opts.on("-f", "--pathFilter=", "Specify file path filter (matched file path only)(default:#{options[:pathFilter]})(\"\" means everything)") do |pathFilter|
		options[:pathFilter] = pathFilter
	end

	opts.on("-i", "--ignoreFile=", "Specify ignore file e.g.ignore.txt or | separator files") do |ignoreFile|
		options[:ignoreFiles] = FileUtil.readFileAsArray(ignoreFile) if !ignoreFile.include?("|")
		options[:ignoreFiles] = ignoreFile.split("|") if options[:ignoreFiles].empty?
		options[:ignoreFiles] = StrUtil.getRegexpArrayFromArray( options[:ignoreFiles] )
	end

	opts.on("", "--ignoreInitialCommit", "Specify if ignore initial commit (default:#{options[:ignoreInitialCommit]})") do
		options[:ignoreInitialCommit] = true
	end

	opts.on("-x", "--ignoreCommits=", "Specify exceptional commit file Note:full sha1 list") do |ignoreCommits|
		options[:ignoreCommits] = FileUtil.readFileAsArray(ignoreCommits)
	end

	opts.on("-a", "--filterAuthorMatch=", "Specify if match-only-filter for git blame result (default:#{options[:filterAuthorMatch]})") do |filterAuthorMatch|
		options[:filterAuthorMatch] = filterAuthorMatch
	end

	opts.on("-s", "--surpressNonIssue", "Specify if surpress non issues e.g. syntaxError (default:#{options[:surpressNonIssue]})") do
		options[:surpressNonIssue] = true
	end

	opts.on("-t", "--execTimeout=", "Specify time out (sec) of cppcheck execution (default:#{options[:execTimeOut]})") do |execTimeOut|
		execTimeOut = execTimeOut.to_i
		options[:execTimeOut] = execTimeOut if execTimeOut
	end

	opts.on("-j", "--numOfThreads=", "Specify number of threads to analyze (default:#{options[:numOfThreads]})") do |numOfThreads|
		numOfThreads = numOfThreads.to_i
		options[:numOfThreads] = numOfThreads if numOfThreads
	end

	opts.on("-l", "--enableLinkInSummary", "Enable link in summary.md to each detail report.md. Note that this is only available in markdown.") do
		options[:enableLinkInSummary] = true
	end

	opts.on("-c", "--codeLink=", "Set code link such as gitlies, etc. Note that this is only available if repo's manifest is available and markdown") do |codeLink|
		codeLink = codeLink.slice(0, codeLink.length-1) if codeLink.end_with?("/")
		options[:codeLink] = codeLink
	end

	opts.on("", "--verbose", "Enable verbose status output") do
		options[:verbose] = true
	end
end.parse!

componentPaths = []
pathGitPaths = {}

if ARGV.length < 1 then
	puts opt_parser
	exit(-1)
else
	isDirectory = FileTest.directory?(ARGV[0])
	if !isDirectory  then
		puts ARGV[0] + " is not found"
		exit(-1)
	else
		componentPaths, pathGitPaths = RepoUtil.getPathesFromManifest( ARGV[0] )
		if componentPaths.empty? then
			ARGV.each do |aPath|
				componentPaths << aPath if FileTest.directory?(aPath)
			end
		end
	end
end

puts "ignoreFiles=#{options[:ignoreFiles]}" if options[:verbose]
puts "ignoreCommit=#{options[:ignoreCommits]}" if options[:verbose]

# AND filter
if options[:pathFilter] then
	_componentPaths = []
	componentPaths.each do | aComponentPath |
		_componentPaths << aComponentPath if aComponentPath.include?( options[:pathFilter] ) || aComponentPath.match( options[:pathFilter] )
	end
	componentPaths = _componentPaths
end

# excluding filter
if options[:ignoreFiles] then
	_componentPaths = []
	componentPaths.each do | aComponentPath |
		_componentPaths << aComponentPath if !StrUtil.matches?( aComponentPath, options[:ignoreFiles] )
	end
	componentPaths = _componentPaths
end

puts "componentPaths=#{componentPaths}" if options[:verbose]

taskMan = ThreadPool.new( options[:numOfThreads].to_i )
componentPaths.each do | aPath |
	taskMan.addTask( CppCheckExecutor.new( resultCollector, aPath, options ) )
end
taskMan.executeAll()
taskMan.finalize()

_result = resultCollector.getResult()
_result = _result.sort

# filter author match
filterAuthorMatch = options[:filterAuthorMatch]
surpressNonIssue = options[:surpressNonIssue]
if filterAuthorMatch || surpressNonIssue then
	_result.each do |path, theResult|
		_theResults = []
		theResult[:results].each do |aResult|
			validResult = true
			validResult = validResult & (
				( !aResult.has_key?(:author) 		|| aResult[:author].match?(filterAuthorMatch) ) |
				( !aResult.has_key?(:authorMail) 	|| aResult[:authorMail].match?(filterAuthorMatch) ) ) if filterAuthorMatch
			validResult = validResult & (
				( !aResult.has_key?("line") 		|| aResult["line"] != "0" ) &
				( !aResult.has_key?("id")			|| ( aResult["id"] != "syntaxError" && aResult["id"] != "unknownMacro" ) ) &
				( !aResult.has_key?("severity") 	|| aResult["severity"] != "information" ) ) if surpressNonIssue

			_theResults << aResult if validResult
		end
		theResult[:results] = _theResults
	end

	__result = {}
	_result.each do |path, theResult|
		__result[path] = theResult if !theResult[:results].empty?
	end
	_result = __result
end

# ensure report out path
FileUtil.ensureDirectory(options[:reportOutPath])

# create summary report
if options[:mode] == "summary" || options[:mode] == "all"
	results = []
	_result.each do |path, theResult|
		theSummary = {}
		theResult[:results] = theResult[:results].uniq
		theResult[:results].each do |aResult|
			if aResult.has_key?("severity") then
				severity = aResult["severity"]
				theSummary[severity] = 0 if !theSummary.has_key?(severity)
				theSummary[severity] = theSummary[severity] + 1
			end
		end
		if !theSummary.empty? then
			if !theResult[:results].empty? then
				result = {}
				result["moduleName"] = theResult[:name]
				result["path"] = theResult[:path]
				result = result.merge(theSummary)
				results << result
			end
		end
	end

	SUMMARY_KEYS = ["error", "warning", "performance", "style", "information"]
	results.sort! do |a, b|
		vecA = []
		vecB = []
		SUMMARY_KEYS.each do |key|
			if a.has_key?(key) && b.has_key?(key) then
				vecA << -a[key].to_i
				vecB << -b[key].to_i
			end
		end
		vecA <=> vecB
	end

	if options[:enableLinkInSummary] && reporter == MarkdownReporter then
		reported = {}
		results.each do |aResult|
			aModuleName = aResult["moduleName"]
			if reported.has_key?(aModuleName) then
				aModuleName = aResult["path"].to_s.gsub("/","_")
			end
			reported[aModuleName] = true
			aResult["moduleName"] = "[#{aResult["moduleName"]}](#{aModuleName}.md)"
		end
	end

	_reporter = reporter.new( options[:reportOutPath] ? "#{options[:reportOutPath]}/summary" : options[:reportOutPath] )
	_reporter.report( results, options[:summarySection] )
	_reporter.close()
end


# create per-component report
if options[:mode] == "detail" || options[:mode] == "all" then
	reported = {}
	_result.each do |moduleName, theResult|
		results = theResult[:results]
		theModulePath = theResult[:path]
		theModulePath = theModulePath.slice(1, theModulePath.length) if theModulePath.start_with?("/")
		theHead = GitUtil.getHeadCommitId(theResult[:fullPath])
		theHead = "HEAD" if !theHead

		#results = results.sort_by { |h| h.values_at("filename", "line") }
		tmp = {}
		results.each do |aResult|
			tmp[ aResult["filename"] ] = [] if !tmp.has_key?( aResult["filename"] )
			tmp[ aResult["filename"] ] << aResult
		end
		tmp.each do | filename, aResult |
			aResult = aResult.uniq
			tmp[filename] = aResult.sort do |a, b|
				a["line"].to_i <=> b["line"].to_i
			end
		end
		results = []
		tmp.each do | filename, aResults |
			aResults.each do | aResult |
				if reporter == MarkdownReporter then
					aResult[:theLine] = "```#{aResult[:theLine]}```" if aResult.has_key?(:theLine)
					if options[:codeLink] && aResult["line"] then
						gitPath = CodeWebHelper.getRobustGitPath( pathGitPaths, theModulePath )
						if gitPath then
							aResult["line"] = CodeWebHelper.getCodeLink( options[:codeLink], gitPath, theHead, filename, aResult["line"] )
						end
					end
				end

				results << aResult
			end
		end

		reportFilename = options[:reportOutPath] ? "#{options[:reportOutPath]}/#{theResult[:name]}" : options[:reportOutPath]
		if reported.has_key?(reportFilename) then
			_convertedPath = theResult[:path].to_s.gsub("/","_")
			reportFilename = options[:reportOutPath] ? "#{options[:reportOutPath]}/#{_convertedPath}" : reportFilename
		end
		reported[reportFilename] = true
		_reporter = reporter.new( reportFilename )
		_reporter.report( results, options[:detailSection] )
		_reporter.close()
	end
end