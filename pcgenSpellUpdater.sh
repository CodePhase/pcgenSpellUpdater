#!/bin/bash
# License: GPLv3
# Author: CodePhase

# Global args
oldIFS=''
sourceHtmlFile=''
pcgenFile=''

declare -a arrSpellEntryLines
declare -a ARRSPELLSCHOOLS=( Abjuration Conjuration Divination Enchantment Evocation Illusion Necromancy Transmutation )

function saveIfs {
  [ -v IFS ] && oldIFS="$IFS" || unset oldIFS
}

function restoreIfs {
  [ -v oldIFS ] && IFS="$oldIFS" || unset IFS
}

function getArgs {
  while [[ $# -gt 0 ]]; do
    case $1 in
      '-h'|'--htmlfile')
        shift
        sourceHtmlFile="$1"
        shift
        ;;
      '-p'|'--pcgenfile')
        shift
        pcgenFile="$1"
        shift
        ;;
      '--dry')
        dryRun=1
        shift
        ;;
      '--debug')
        debug=1
        shift
        ;;
      *)
        echo "Unrecognized arg $1. Exiting"
        exit 1
        ;;
    esac
  done

  if [ ! -f "${sourceHtmlFile}" ]; then
    echo "ERROR: ${sourceHtmlFile} is not accessible." >&2
    exit 1
  fi

  if [ -z "$dryRun" ] && [ ! -f "${pcgenFile}" ]; then
    echo "ERROR: ${pcgenFile} is not accessible." >&2
    exit 1
  fi
}

function htmlSpellScrape {
  saveIfs
  IFS=$'\n\r'
  unset spellSecFound

  # Section REGEX's
  SPELLSECSTART='<h1 [^>]+>Spell Descriptions</h1>'
  unset spellSecEndUpdated
  SPELLSECEND='<div .+ data-next-title='
  SPELLENTSTART='<h3 .+</h3>'
  SPELLENTEND1='<hr class="separator">'
  SPELLENTEND2='<!-- #endregion -->'
  SPELLCOMPEND='</div>'

  # Spell Entry REGEX's
  SPELLSCHOOL1='<p .+><em>[a-zA-Z]+ Cantrip .+</em></p>'
  SPELLSCHOOL2='<p .+><em>Level [0-9] [a-zA-Z]+ .+</em></p>'
  SPELLCASTINGTIME='<strong>Casting Time:</strong>'
  SPELLRANGE='<strong>Range:</strong>'
  SPELLCOMPONENTS='<strong>Components:</strong>'
  SPELLDURATION='<strong>Duration:</strong>'
  SPELLSAVINGTHROW='a [a-zA-Z]+ saving throw'
  STATBLOCKSTART='<div class="stats"'
  STATBLOCKSTART='<div class="stat-block"'
  STATBLOCKEND='</div>'

  while read -r htmlFileLine; do
    # Skip through html file until spell description section
    if [[ "$htmlFileLine" =~ $SPELLSECSTART ]]; then
      spellSecFound=1
      debug "Found Spell Description Section start: ${htmlFileLine}"
      continue
    elif [ -z "$spellSecEndUpdated" ] && [ -n "$spellSecFound" ] && [[ "${htmlFileLine}" =~ $SPELLSECEND ]]; then
      # I know you aren't supposed to change CONSTANT values, but sources can differ
      SPELLSECEND="$(sed -En 's,<div .+ data-next-title="([^"]+).+,\1,p' <<< "${htmlFileLine}")"
      spellSecEndUpdated=1
      debug "Set SPELLSECEND to ${SPELLSECEND}"
      continue
    #Some spells contain stat blocks. Skip those.
    elif [ -n "$spellSecFound" ] && [[ "${htmlFileLine}" =~ $STATBLOCKSTART ]]; then
      statBlockFound=1
      continue
    elif [ -n "$statBlockFound" ]; then
      if [[ "${htmlFileLine}" =~ $STATBLOCKEND ]]; then
        unset statBlockFound
      else
       continue
      fi
    elif [ -n "$spellSecFound" ] && [[ "${htmlFileLine}" =~ $SPELLENTSTART ]]; then
      # Found a spell entry. Process it line by line
      spellEntryFound=1
      debug "Found Spell Entry start: ${htmlFileLine}"
      # Create a new entry array and store the spell title
      declare -gA arrSpellEntry
      debug "Setting spell entry title"
      arrSpellEntry[title]="$(sed -En 's,<h3 .+>(([^<])+)</a></h3>$,\1,p' <<< "${htmlFileLine//’/\'}")"
      debug "Finished setting spell entry title"
      continue
    elif [ -n "$spellEntryFound" ]; then
      debug "We know spellEntryFound is set"
      if [[ "${htmlFileLine}" =~ $SPELLENTEND1 ]] || [[ "${htmlFileLine}" =~ $SPELLENTEND2 ]]; then
        arrSpellEntry[description]="${arrSpellEntry[description]//;./.}"
        debug "\nDEBUG: **************\nDEBUG: Spell Title: ${arrSpellEntry[title]}"
        if [ -n "$debug" ]; then
          for key in "${!arrSpellEntry[@]}"; do
            debug "${key} - ${arrSpellEntry[${key}]}"
          done
        fi
        [ -n "${arrSpellEntry[savingthrow]}" ] && spellEntry_pcgen_savingthrow="SAVEINFO:${arrSpellEntry[savingthrow]}"
        [ -n "${spellEntryIsRitual}" ] && spellEntry_pcgen_ritual="SUBSCHOOL:Ritual"
        newSpellEntry_pcgen="${arrSpellEntry[title]}						KEY:${arrSpellEntry[title]}						TYPE:Arcane.Divine.Spell	SCHOOL:${arrSpellEntry[school]}		${spellEntry_pcgen_ritual}		COMPS:${arrSpellEntry[components]}																																																											CASTTIME:${arrSpellEntry[castingtime]}																		RANGE:${arrSpellEntry[range]}					DURATION:${arrSpellEntry[duration]}				${spellEntry_pcgen_savingthrow}		SOURCEPAGE:p.211	DESC:${arrSpellEntry[description]/% /}"
        unset spellEntry_pcgen_savingthrow
        unset spellEntry_pcgen_ritual
        unset spellEntryIsRitual
        # Test if spell entry is present in pcgen file
        unset spellEntry_pcgen
        spellEntry_pcgen="$(grep -P "^${arrSpellEntry[title]}\t|\t${arrSpellEntry[title]}\t" ${pcgenFile})"
        if [ $? -eq 0 ]; then
          # True: Update entry
          if [ -n "$debug" ]; then
            debug "Found existing entry of spell '${arrSpellEntry[title]}' in pcgen file\nDEBUG: ${spellEntry_pcgen}"
          fi
          if [ -z "$dryRun" ]; then
            debug "Replacing with\nDEBUG: ${newSpellEntry_pcgen}"
            sed -i -e "s|^${arrSpellEntry[title]}\t.*|${newSpellEntry_pcgen}|" -e "s|.*\t${arrSpellEntry[title]}\t.*|${newSpellEntry_pcgen}|" ${pcgenFile}
          else
            debug "Skipping file update due to --dryrun"
            debug "Would have run:"
            # We can't use the 'debug' function for this next call because the '\t' will get literally expanded in our output due to debug's 'echo -e' usage
            echo "DEBUG: sed -i -e \"s|^${arrSpellEntry[title]}\t.*|${newSpellEntry_pcgen}|\" -e \"s|.*\t${arrSpellEntry[title]}\t.*|${newSpellEntry_pcgen}|\" ${pcgenFile}" >&2
          fi
        else
          # False: Add new entry after previous entry
          if [ -z "$dryRun" ]; then
            debug "Existing entry of spell '${arrSpellEntry[title]}' not found; adding."
            echo -e "${newSpellEntry_pcgen}" >> ${pcgenFile}
          else
            debug "Skipping file update due to --dryrun"
            debug "Would have run:"
            debug "echo -e \"${newSpellEntry_pcgen}\" >> ${pcgenFile}"
          fi
        fi
        unset spellEntryFound
        # Reset Spell Entry Description section flag
        unset spellEntryDescStart
        # Empty the previous entry array
        unset arrSpellEntry
        debug "Found Spell Entry end: ${htmlFileLine}"
        continue
      else
        debug "htmlFileLine - ${htmlFileLine}"
        # Scrape spell entry
        # Activate spell description section if we've reached the end of the spell components section
        if [[ "${htmlFileLine}" =~ $SPELLCOMPEND ]]; then
          spellEntryDescStart=1
          continue
        fi

        if [ -n "${spellEntryDescStart}" ]; then
          # Capture Description
          # Format Description: remove tag blocks and replace line breaks with spaces
          debug "Start spell ent desc clean 1"
          debug "Description line: ${htmlFileLine}"
          htmlFileLineClean="$(sed -E -e 's|<p [^>]+>||g' -e 's|</p>| |g' -e 's|</?a[^>]*>||g' -e 's|</?strong>||g' -e 's|</?em>||g' -e 's|</?figure[^>]*>||g' -e 's,<span[^>]*>[^<]*</span>,,g' -e 's,<figcaption>.*</figcaption>,,g' -e 's|</?ul[^>]*>||g' -e 's|<li [^>]*>|* |g' -e 's|</li>||g' -e 's|<img[^>]*>||g' <<< "${htmlFileLine}")"
          debug "htmlFileLineClean 1: ${htmlFileLineClean}"
          # Format Description: replace tables with sentence-based lists
          debug "Start spell ent desc clean 2"
          htmlFileLineClean="$(sed -E -e 's|<table[^>]*>||g' -e 's|</table>|. |g' -e 's|</?caption>||g' -e 's|<h4[^>]*>||g' -e 's|(([a-zA-Z0-9 ])+)</h4>|\1:|g' -e 's|</?thead>||g' -e 's|<th>[^<]*</th>||g' -e 's|</?tbody>||g' -e 's|</?tr>||g' <<< "${htmlFileLineClean}")"
          debug "htmlFileLineClean 2: ${htmlFileLineClean}"
          if ( grep -qE '<td>.+</td>' <<< "${htmlFileLineClean}") && [ -z "$tdSet" ]; then
            tdSet=1
            debug "Start spell ent desc clean 3"
            htmlFileLineClean="$(sed -E 's|<td>([^<]+)</td>| \1 - |g' <<< "${htmlFileLineClean}")"
            debug "htmlFileLineClean 3: ${htmlFileLineClean}"
          elif ( grep -qE '<td>.+</td>' <<< "${htmlFileLineClean}") && [ -n "$tdSet" ]; then
            unset tdSet
            debug "Start spell ent desc clean 4"
            htmlFileLineClean="$(sed -E 's|<td>([^<]+)</td>|\1;|g' <<< "${htmlFileLineClean}")"
            debug "htmlFileLineClean 4: ${htmlFileLineClean}"
          fi
          # Discern saving throw type(s) from Description
          if [[ "${htmlFileLineClean}" =~ $SPELLSAVINGTHROW ]]; then
            debug "Start saving throw detection"
            arrSpellEntry[savingthrow]="$(sed -En 's,.+a (([a-zA-Z])+) saving throw.+,\1,p' <<< "${htmlFileLineClean}")"
          fi
          arrSpellEntry[description]="${arrSpellEntry[description]}${htmlFileLineClean//’/\'}"
        else
          # Capture Spell Components
          # Store fields: School, Casting Time, Range, Components, Duration
          if [[ "${htmlFileLine}" =~ $SPELLSCHOOL1 ]] || [[ "${htmlFileLine}" =~ $SPELLSCHOOL2 ]]; then
            debug "Start spell ent school"
            arrSpellEntry[school]="$(sed -En -e 's,<p .+>(([a-zA-Z])+) Cantrip .+</p>,\1,p' -e 's,<p .+>Level [0-9] (([a-zA-Z])+) .+</p>,\1,p' <<< "${htmlFileLine//’/\'}")"
          elif [[ "${htmlFileLine}" =~ $SPELLCASTINGTIME ]]; then
            debug "Start spell ent casting time"
            arrSpellEntry[castingtime]="$(sed -En -e 's|<a .*>(([a-zA-Z0-9 ])+)</a>|\1|' -e 's|<p .+> (([a-zA-Z0-9 ,()])+)</p>|\1|p' <<< "${htmlFileLine//’/\'}")"
            arrSpellEntry[castingtime]=${arrSpellEntry[castingtime]/Action/1 Action}
            arrSpellEntry[castingtime]=${arrSpellEntry[castingtime]/Bonus 1 Action/1 Bonus Action}
            if (grep -q 'or Ritual' <<< "${arrSpellEntry[castingtime]}"); then
              spellEntryIsRitual=1
              arrSpellEntry[castingtime]=${arrSpellEntry[castingtime]% or Ritual}
            fi
            debug "Saved Casting Time as ${arrSpellEntry[castingtime]}"
          elif [[ "${htmlFileLine}" =~ $SPELLRANGE ]]; then
            debug "Start spell ent range"
            arrSpellEntry[range]="$(sed -En 's,.*Range:</strong> (([^<])+)</p>,\1,p' <<< "${htmlFileLine//’/\'}")"
            debug "Saved Range as ${arrSpellEntry[range]}"
          elif [[ "${htmlFileLine}" =~ $SPELLCOMPONENTS ]]; then
            debug "Start spell ent components"
            arrSpellEntry[components]="$(sed -En 's,.*Components:</strong> (([^<])+)</p>,\1,p' <<< "${htmlFileLine//’/\'}")"
          elif [[ "${htmlFileLine}" =~ $SPELLDURATION ]]; then
            debug "Start spell ent duration"
            arrSpellEntry[duration]="$(sed -En -e 's|<a .*>(([^<])+)</a>|\1|' -e 's|<p .+> (([^<])+)</p>|\1|p' <<< "${htmlFileLine//’/\'}")"
          fi
        fi
      fi
    # Detect section end and exit
    elif [ -n "$spellSecFound" ] && [[ "${htmlFileLine}" =~  $SPELLSECEND ]]; then
      debug "Found Spell Description Section end: ${htmlFileLine}"
      unset spellSecFound
      restoreIfs
      break
    fi
  done < "${sourceHtmlFile}"
}

function pcgenSpellScrape {
  declare -a pcgenRemovalSpells=( )

  # Test if each pcgen spell entry is present in html file
  while read -r pcgenFileLine; do
    debug "PCGEN File Line: ${pcgenFileLine}"
    if [[ "${pcgenFileLine}" =~ ^[^.]+\.[mM][oO][dD][[:space:]] ]]; then
      # This is a modification line we can ignore
      continue
    elif [[ "${pcgenFileLine}" =~ ^[[:alnum:]] ]]; then
      # This should be an entry we need to pay attention to
      spellEntry_pcgen_title="$(awk -F '\t' '{print $1}' <<< "${pcgenFileLine}")"
      debug "Got pcgen file spell title '${spellEntry_pcgen_title}'"
      if ! grep -qE "<h3 .+>${spellEntry_pcgen_title//\'/’}</a></h3>$" "${sourceHtmlFile}"; then
        # False: Remove spell entry from pcgen file
        pcgenRemovalSpells+=( "${spellEntry_pcgen_title}" )
      fi
    fi
  done < "${pcgenFile}"

  if [ ${#pcgenRemovalSpells[@]} -gt 0 ]; then
    debug "There are ${#pcgenRemovalSpells[@]} spells to remove from the pcgen file ${pcgenFile}"
    for pcgenRemovalSpell in "${pcgenRemovalSpells[@]}"; do
      if [ -z "$dryRun" ]; then
        debug "Removing spell ${pcgenRemovalSpell} from pcgenfile"
        sed -i "/^${pcgenRemovalSpell}\t/d" "${pcgenFile}"
      else
        debug "Skipping file update due to --dryrun"
        debug "Would have run:"
        echo "sed -i \"/^${pcgenRemovalSpell}\t/d\" \"${pcgenFile}\""
      fi
    done
  fi
}

function debug {
  [ -n "$debug" ] && echo -e "DEBUG: ${1}" >&2
}

getArgs "$@"

htmlSpellScrape
pcgenSpellScrape

exit 0
