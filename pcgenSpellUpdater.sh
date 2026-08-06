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
      *)
        echo "Unrecognized arg $1. Exiting"
        exit 1
        ;;
    esac
  done
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
echo "Found Spell Description Section start: ${htmlFileLine}"
      continue
    elif [ -z "$spellSecEndUpdated" ] && [ -n "$spellSecFound" ] && [[ "${htmlFileLine}" =~ $SPELLSECEND ]]; then
      # I know you aren't supposed to change CONSTANT values, but sources can differ
      SPELLSECEND="$(sed -En 's,<div .+ data-next-title="([^"]+).+,\1,p' <<< "${htmlFileLine}")"
      spellSecEndUpdated=1
echo "Set SPELLSECEND to ${SPELLSECEND}"
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
      spellEntryFound=1
echo "Found Spell Entry start: ${htmlFileLine}"
      # Create a new entry array and store the spell title
      declare -gA arrSpellEntry
#echo "Setting spell entry title"
      arrSpellEntry[title]="$(sed -En 's,<h3 .+>(([^<])+)</a></h3>$,\1,p' <<< "${htmlFileLine//’/\'}")"
#echo "Finished setting spell entry title"
      continue
    elif [ -n "$spellEntryFound" ]; then
#echo "DEBUG: We know spellEntryFound is set"
      if [[ "${htmlFileLine}" =~ $SPELLENTEND1 ]] || [[ "${htmlFileLine}" =~ $SPELLENTEND2 ]]; then
        arrSpellEntry[description]="${arrSpellEntry[description]//;./.}"
echo
echo "**************"
echo "DEBUG: Spell Title: ${arrSpellEntry[title]}"
for key in "${!arrSpellEntry[@]}"; do
  echo "DEBUG: ${key} - ${arrSpellEntry[${key}]}"
done
        unset spellEntryFound
        # Reset Spell Entry Description section flag
        unset spellEntryDescStart
        # Empty the previous entry array
        unset arrSpellEntry
#echo "Found Spell Entry end: ${htmlFileLine}"
        continue
      else
#echo "DEBUG: htmlFileLine - ${htmlFileLine}"
        # Scrape spell entry
        # Activate spell description section if we've reached the end of the spell components section
        if [[ "${htmlFileLine}" =~ $SPELLCOMPEND ]]; then
          spellEntryDescStart=1
          continue
        fi

        if [ -n "${spellEntryDescStart}" ]; then
          # Capture Description
          # Format Description: remove tag blocks and replace line breaks with spaces
#echo "Start spell ent desc clean 1"
echo "Description line: ${htmlFileLine}"
          htmlFileLineClean="$(sed -E -e 's|<p [^>]+>||g' -e 's|</p>| |g' -e 's|</?a[^>]*>||g' -e 's|</?strong>||g' -e 's|</?em>||g' -e 's|</?figure[^>]*>||g' -e 's,</?span[^>]*>[a-zA-Z0-9 ]*,,g' -e 's,</?figcaption[^>]*>[a-zA-Z0-9 ]*,,g' -e 's|</?ul[^>]*>||g' -e 's|<li [^>]*>|* |g' -e 's|</li>||g' -e 's|<img[^>]+>||g' <<< "${htmlFileLine}")"
#echo "htmlFileLineClean 1: ${htmlFileLineClean}"
          # Format Description: replace tables with sentence-based lists
#echo "Start spell ent desc clean 2"
          htmlFileLineClean="$(sed -E -e 's|<table[^>]*>||g' -e 's|</table>|. |g' -e 's|</?caption>||g' -e 's|<h4[^>]*>||g' -e 's|(([a-zA-Z0-9 ])+)</h4>|\1:|g' -e 's|</?thead>||g' -e 's|<th>[^<]*</th>||g' -e 's|</?tbody>||g' -e 's|</?tr>||g' <<< "${htmlFileLineClean}")"
#echo "htmlFileLineClean 2: ${htmlFileLineClean}"
          if ( grep -qE '<td>.+</td>' <<< "${htmlFileLineClean}") && [ -z "$tdSet" ]; then
            tdSet=1
#echo "Start spell ent desc clean 3"
            htmlFileLineClean="$(sed -E 's|<td>([^<]+)</td>| \1 - |g' <<< "${htmlFileLineClean}")"
#echo "htmlFileLineClean 3: ${htmlFileLineClean}"
          elif ( grep -qE '<td>.+</td>' <<< "${htmlFileLineClean}") && [ -n "$tdSet" ]; then
            unset tdSet
#echo "Start spell ent desc clean 4"
            htmlFileLineClean="$(sed -E 's|<td>([^<]+)</td>|\1;|g' <<< "${htmlFileLineClean}")"
#echo "htmlFileLineClean 4: ${htmlFileLineClean}"
          fi
          # Discern saving throw type(s) from Description
          if [[ "${htmlFileLineClean}" =~ $SPELLSAVINGTHROW ]]; then
#echo "Start saving throw detection"
            arrSpellEntry[savingthrow]="$(sed -En 's,.+a (([a-zA-Z])+) saving throw.+,\1,p' <<< "${htmlFileLineClean}")"
          fi
          arrSpellEntry[description]="${arrSpellEntry[description]}${htmlFileLineClean//’/\'}"
        else
          # Capture Spell Components
          # Store fields: School, Casting Time, Range, Components, Duration
          if [[ "${htmlFileLine}" =~ $SPELLSCHOOL1 ]] || [[ "${htmlFileLine}" =~ $SPELLSCHOOL2 ]]; then
#echo "Start spell ent school"
            arrSpellEntry[school]="$(sed -En -e 's,<p .+>(([a-zA-Z])+) Cantrip .+</p>,\1,p' -e 's,<p .+>Level [0-9] (([a-zA-Z])+) .+</p>,\1,p' <<< "${htmlFileLine//’/\'}")"
          elif [[ "${htmlFileLine}" =~ $SPELLCASTINGTIME ]]; then
#echo "Start spell ent casting time"
            arrSpellEntry[castingtime]="$(sed -En -e 's|<a .*>(([a-zA-Z0-9 ])+)</a>|\1|' -e 's|<p .+> (([a-zA-Z0-9 ,()])+)</p>|\1|p' <<< "${htmlFileLine//’/\'}")"
            arrSpellEntry[castingtime]=${arrSpellEntry[castingtime]/Action/1 Action}
            arrSpellEntry[castingtime]=${arrSpellEntry[castingtime]/Bonus 1 Action/1 Bonus Action}
            if (grep -q 'or Ritual' <<< "${arrSpellEntry[castingtime]}"); then
              spellEntryIsRitual=1
              arrSpellEntry[castingtime]=${arrSpellEntry[castingtime]% or Ritual}
            fi
#echo "DEBUG: saved Casting Time as ${arrSpellEntry[castingtime]}"
          elif [[ "${htmlFileLine}" =~ $SPELLRANGE ]]; then
#echo "Start spell ent range"
            arrSpellEntry[range]="$(sed -En 's,.*Range:</strong> (([^<])+)</p>,\1,p' <<< "${htmlFileLine//’/\'}")"
#echo "DEBUG: saved Range as ${arrSpellEntry[range]}"
          elif [[ "${htmlFileLine}" =~ $SPELLCOMPONENTS ]]; then
#echo "Start spell ent components"
            arrSpellEntry[components]="$(sed -En 's,.*Components:</strong> (([^<])+)</p>,\1,p' <<< "${htmlFileLine//’/\'}")"
          elif [[ "${htmlFileLine}" =~ $SPELLDURATION ]]; then
#echo "Start spell ent duration"
            arrSpellEntry[duration]="$(sed -En -e 's|<a .*>(([^<])+)</a>|\1|' -e 's|<p .+> (([^<])+)</p>|\1|p' <<< "${htmlFileLine//’/\'}")"
          fi
        fi
        # Test if spell entry is present in pcgen file
          # True: Update entry
          # False: Add new entry after previous entry
      fi
    # Detect section end and exit
    elif [ -n "$spellSecFound" ] && [[ "${htmlFileLine}" =~  $SPELLSECEND ]]; then
echo "Found Spell Description Section end: ${htmlFileLine}"
      unset spellSecFound
      restoreIfs
      break
    fi
  done < "${sourceHtmlFile}"
}

function pcgenSpellScrape {
  # Test if each pcgen spell entry is present in html file
    # False: Remove spell entry from pcgen file
  echo "We will have something here soon."
}

function getHtmlSpellEntry {
  spellEntry="$(sed -n "/id=\"${1}\"/,/^<hr class=\"separator\">/p" "${sourceHtmlFile}")"
  [ -n "${spellEntry}" ] && spellEntryToArray "${spellEntry}" || echo "Spell entry ${1} not found in ${sourceHtmlFile}"
}

function parseHtmlSpellEntry {
  # Read HTML block arg lines
  read -d '' -r -a arrSpellEntryLines <<< "$1"
}

function parsePcgenSpellEntry {
  # Read tab-separated single line
  echo "We will have something here soon."
}

getArgs "$@"

htmlSpellScrape
#pcgenSpellScrape

exit 0
