vim9script

import './popup.vim'
import './job.vim'

var data_dir = '~/.local/share/devdocs'
var devdocs_site_url = 'https://devdocs.io'
var devdocs_cdn_url = 'https://documents.devdocs.io'

def Extract(outdir: string): bool
    var tmpdir = $'{outdir}.tmp'
    if !$'{tmpdir}/index.json'->filereadable() || !$'{tmpdir}/db.json'->filereadable()
        :echohl ErrorMsg | echoerr 'Missing {index,db}.json' | echohl None
        return false
    endif
    var db: dict<any>
    try
        # 100 MB json file takes ~900 ms to read and decode
        db = $'{tmpdir}/db.json'->readfile()->join()->json_decode()
    catch
        :echohl ErrorMsg | echoerr $'Failed to read devdocs db.json ({v:exception})' | echohl None
        return false
    endtry
    for [fname, content] in db->items()
        var dir = $'{tmpdir}/{fname->fnamemodify(":h")}'
        if !dir->isdirectory() && !mkdir(dir, 'p')
            :echohl ErrorMsg | echoerr $'Failed to create {dir}' | echohl None
            return false
        endif
        var filename = $'{tmpdir}/{fname}.html'
        if [content]->writefile(filename) == -1
            :echohl ErrorMsg | echoerr $'Failed to write {filename}' | echohl None
            return false
        endif
    endfor
    if outdir->isdirectory() && outdir->delete('rf') != 0
        :echohl ErrorMsg | echoerr $'Failed to remove {outdir}' | echohl None
        return false
    endif
    $'mv {tmpdir} {outdir}'->system()
    if v:shell_error != 0
        :echohl ErrorMsg | echoerr $'Failed to rename {outdir}' | echohl None
        return false
    endif
    return true
enddef

def FetchSlug(entry: dict<any>)
    if entry.slug->empty() | return | endif
    var outdir = $'{data_dir}/{entry.slug}'->expand()->fnameescape()
    var tmpdir = $'{outdir}.tmp'
    if tmpdir->isdirectory() && tmpdir->delete('rf') != 0
        :echohl ErrorMsg | echoerr $'Failed to remove {tmpdir}' | echohl None
        return
    endif
    def Text(t: string): list<string>
        return [t, '', 'This may take a few minutes', '', '<Esc> to dismiss window', '<C-c> to abort job']
    enddef
    var task: any
    var notif: popup.NotificationPopup
    var aborted = false
    notif = popup.NotificationPopup.new(Text($'Downloading {entry.db_size} bytes ...'),
        () => {
            # <C-c> was pressed
            if task->type() == v:t_object
                task.Stop()
            endif
            aborted = true
        })
    var url = $'{devdocs_cdn_url}/{entry.slug}/{{index,db}}.json?{entry.mtime}'
    task = job.AsyncCmd.new(
        $'curl -fsSL --remote-name-all --output-dir {tmpdir} --create-dirs "{url}"',
        (msg: string) => {
            if !aborted && $'{tmpdir}/index.json'->filereadable() && $'{tmpdir}/db.json'->filereadable()
                notif.Update(Text('Extracting archive ...'))
                if Extract(outdir)
                    notif.Update(Text('Success!'))
                    :sleep 300m
                endif
            endif
            notif.Close()
        })
enddef

def ShowMenu(items: list<dict<any>>)
    def Filter(lst: list<dict<any>>, prompt: string): list<any>
        if prompt->empty()
            return [lst, [lst]]
        else
            var pat = prompt->trim()
            var matches = lst->matchfuzzypos(pat, {key: "text"})
            return [lst, matches]
        endif
    enddef
    # popup.FilterMenu("Devdocs Install", items,
    popup.FilterMenuPopup.new().PopupCreate('Devdocs Install',
        items,
        (res, key) => {
            FetchSlug(res.data)
        },
        null_function,
        Filter)
enddef

export def Install()
    job.AsyncCmd.new($'curl -fsSL {devdocs_site_url}/docs.json',
        (msg: string) => {
            var docs: list<any>
            try
                docs = msg->json_decode()
            catch
                :echohl ErrorMsg | echoerr $'Failed to fetch devdocs index ({v:exception})' | echohl None
                return
            endtry
            var items = docs->mapnew((_, v) => {
                return {text: v.slug, data: v}
            })
            ShowMenu(items)
        })
enddef
