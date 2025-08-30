from format_bank_xml import process_dialogue


def test_split_sentences() -> None:
    # This test is no longer needed since we use lexer/parser approach
    pass


def test_format() -> None:
    """Test that a [new]\n tag is inserted between character speches,
    \n should be inserted after a punctuation if it's not the end of the speach
    Word wrapping should be applied to each sentence."""
    formatted = process_dialogue("""Edge: And here I am all
 pumped up to fight
 that bastard!

 Ah, well...
 can't be breaking a sweat
 in front of the ladies.

Golbeze: Cecil...[end]""")

    assert (
        formatted
        == """Edge: And here I am all pumped up
to fight that bastard!
Ah, well... can't be breaking a sweat in
front of the ladies.[new]
Golbeze: Cecil...[end]"""
    )


def test_format2() -> None:
    formatted = process_dialogue("""Soldier: Yes sir!



Soldier: The monsters
 have been increasing lately
 though...

Soldier: There's just too
 many of them nowadays.


Cecil: Is something...
 happening?[end]""")

    assert (
        formatted
        == """Soldier: Yes sir![new]
Soldier: The monsters have been
increasing lately though...[new]
Soldier: There's just too many of them
nowadays.[new]
Cecil: Is something... happening?[end]"""
    )


def test_format3() -> None:
    formatted = process_dialogue("""Soldier: Agh!
Cecil: Are you all right?


Soldier: There's more of them!Cecil: Damn![end]""")

    assert (
        formatted
        == """Soldier: Agh![new]
Cecil: Are you all right?[new]
Soldier: There's more of them![new]
Cecil: Damn![end]"""
    )


def test_formatting_idempotency() -> None:
    first_formatting = process_dialogue("""Soldier: Agh![new]
Cecil: Are you all right?[new]
Soldier: There's more[new]
of them![new]
Cecil: Damn![end]""")

    second_formatting = process_dialogue(first_formatting)

    assert first_formatting == second_formatting


def test_formatting_speech_without_the_character_visible() -> None:
    """speech between '«' '»' should be put on a new window"""
    assert (
        process_dialogue(
            """«Je suis votre guide pour l'enfer...» «Je suis l'un des quatre Empereurs de seigneur Golbeze... Scarmiglione de la Terre... Il est temps que dînent mes précieux morts-vivants!» Cecil: Comment!?[end]"""
        )
        == """«Je suis votre guide pour l'enfer...»[new]
«Je suis l'un des quatre Empereurs de seigneur Golbeze... Scarmiglione de la Terre... Il est temps que dînent mes précieux morts-vivants!»[new]
Cecil: Comment!?[end]"""
    )


def test_sentences_not_fitting_the_current_window_should_be_moved() -> None:
    assert (
        process_dialogue(
            """Pourquoi avez-vous besoin de ces cristaux? Était-ce parce que les Mythidiens représentaient une menace? Alors pourquoi n'ont-ils pas résisté? Nous ne comprenons pas pourquoi des innocents ont dû périr.[end]"""
        )
        == """Pourquoi avez-vous besoin de ces
cristaux?
Était-ce parce que les Mythidiens
représentaient une menace?[new]
Alors pourquoi n'ont-ils pas résisté?
Nous ne comprenons pas pourquoi des
innocents ont dû périr.[end]"""
    )


def test_character_speech_sentences_not_fitting_the_current_window_should_be_moved() -> (
    None
):
    assert (
        process_dialogue(
            """Cecil: Votre Majesté, nous ne comprenons pas vos intentions. Pourquoi avez-vous besoin de ces cristaux? Était-ce parce que les Mythidiens représentaient une menace? Alors pourquoi n'ont-ils pas résisté? Nous ne comprenons pas pourquoi des innocents ont dû périr.[end]"""
        )
        == """Cecil: Votre Majesté, nous ne
comprenons pas vos intentions.
Pourquoi avez-vous besoin de ces
cristaux?[new]
Était-ce parce que les Mythidiens
représentaient une menace?
Alors pourquoi n'ont-ils pas résisté?[new]
Nous ne comprenons pas pourquoi des
innocents ont dû périr.[end]"""
    )


def test_changing_character_should_introduce_a_new_tag() -> None:
    assert process_dialogue(
        """Soldat: Mais, Capitaine! Soldat: Piller une cité de magiciens qui n'opposent aucune résistance! Cecil: Écoutez bien, vous tous! Le cristal est absolument nécessaire à la prospérité de notre royaume de Baron. Sa Majesté a jugé que les habitants de Mythidia en savaient trop sur les secrets du cristal. Nous sommes l'escadron des Ailes Rouges de Baron, et les ordres de Sa Majesté sont absolus! Soldat: Capitaine...[end]"""
    ) == (
        "Soldat: Mais, Capitaine![new]\n"
        "Soldat: Piller une cité de magiciens qui\n"
        "n'opposent aucune résistance![new]\n"
        "Cecil: Écoutez bien, vous tous!\n"
        "Le cristal est absolument nécessaire à\n"
        "la prospérité de notre royaume de Baron.[new]\n"
        "Sa Majesté a jugé que les habitants de\n"
        "Mythidia en savaient trop sur les secrets\n"
        "du cristal.[new]\n"
        "Nous sommes l'escadron des Ailes\n"
        "Rouges de Baron, et les ordres de Sa\n"
        "Majesté sont absolus![new]\n"
        "Soldat: Capitaine...[end]"
    )

    assert (
        process_dialogue("""Caïn: Qu'est-ce qu'il y a?
Cecil: Je suis désolé, Caïn... Caïn: Pourquoi t'excuses-tu encore? Je t'ai défendu de mon plein gré!![end]""")
        == """Caïn: Qu'est-ce qu'il y a?[new]
Cecil: Je suis désolé, Caïn...[new]
Caïn: Pourquoi t'excuses-tu encore?
Je t'ai défendu de mon plein gré!![end]"""
    )


def test_long_sentence_splitting_within_character_speech() -> None:
    """Sentences should be intelligently grouped based on 4-line dialog box capacity"""
    assert (
        process_dialogue(
            """Tellah: Je ne suis pas en mesure de vaincre quelqu'un d'aussi puissant que lui avec la magie dont je dispose actuellement. Je recherchais la légendaire magie scellée, Météor... Et j'ai senti une forte aura émise de cette montagne. Serait-ce possible, après toutes ces années de recherches..?[end]"""
        )
        == """Tellah: Je ne suis pas en mesure de
vaincre quelqu'un d'aussi puissant que lui
avec la magie dont je dispose
actuellement.[new]
Je recherchais la légendaire magie
scellée, Météor...
Et j'ai senti une forte aura émise de
cette montagne.[new]
Serait-ce possible, après toutes ces
années de recherches..?[end]"""
    )


def test_abbreviation_handling() -> None:
    """M. abbreviation should not be treated as sentence ending"""
    assert (
        process_dialogue(
            """Cecil: Bonjour M. Rosa, comment allez-vous? Nous devons partir maintenant.[end]"""
        )
        == """Cecil: Bonjour M. Rosa,
comment allez-vous?
Nous devons partir maintenant.[end]"""
    )


def test_bank2_variants_end_should_clear_the_state() -> None:
    assert (
        process_dialogue("""Si le capitaine des chevaliers dragons Caïn et Cecil font équipe, cette bague est sûre d'arriver à bon port![end]M.Caïn est intouchable![end]
On dit beaucoup de choses sur sa majesté, mais si elle entendait ça...[end]""")
        == """Si le capitaine des chevaliers dragons
Caïn et Cecil font équipe, cette
bague est sûre d'arriver à bon port![end]
M.Caïn est intouchable![end]
On dit beaucoup de choses sur sa
majesté, mais si elle entendait ça...[end]"""
    )


def test_pointer_49() -> None:
    """[new] should never be preceded by a \n"""
    text = """Cecil: Votre Majesté, nous ne comprenons pas vos intentions.
Pourquoi avez-vous besoin de ces cristaux?
Était-ce parce que les Mythidiens représentaient une menace?
Alors pourquoi n'ont-ils pas résisté?
Nous ne comprenons pas pourquoi des innocents ont dû périr.[end]"""

    expected = """Cecil: Votre Majesté, nous ne
comprenons pas vos intentions.
Pourquoi avez-vous besoin de ces
cristaux?[new]
Était-ce parce que les Mythidiens
représentaient une menace?
Alors pourquoi n'ont-ils pas résisté?[new]
Nous ne comprenons pas pourquoi des
innocents ont dû périr.[end]"""

    result = process_dialogue(text)
    assert result == expected

    # Test idempotency - running it again should give same result
    result2 = process_dialogue(result)
    assert result == result2


def test_break_line_should_not_introduce_spaces() -> None:
    assert (
        process_dialogue(
            """Yang: Il est trop tard! Cecil: Mais qui est en train de combattre les Ailes Rouges? Cid: Malheur! On est touché! On va s'écraser! Accrochez-vous![end]"""
        )
        == """Yang: Il est trop tard![new]
Cecil: Mais qui est en train de
combattre les Ailes Rouges?[new]
Cid: Malheur!
On est touché!
On va s'écraser!
Accrochez-vous![end]"""
    )


def test_bank_2_thingie() -> None:
    text = """T[end]T[end]T[end]T[end]T[end]T[end]T[end]T[end]T[end]T[end]Le trésor de Baron est entreposé ici! C'est interdit![end]"""

    processed = process_dialogue(text)
    assert (
        processed
        == """T[end]T[end]T[end]T[end]T[end]T[end]T[end]T[end]T[end]T[end]Le trésor de Baron est entreposé ici!
C'est interdit![end]"""
    )


def test_mixed_offscreen_and_character_dialog() -> None:
    assert process_dialogue(
        "«Vous êtes de Baron, hein...» Caïn: Qui est là?[music][0x2d] «Partez maintenant et il ne vous fait aucun mal...» Caïn: Montre-toi! «Vous voulez vraiment continuer?»[end]"
    ) == (
        "«Vous êtes de Baron, hein...»[new]\n"
        "Caïn: Qui est là?[music][0x2d][new]\n"
        "«Partez maintenant et il ne vous fait aucun mal...»[new]\n"
        "Caïn: Montre-toi![new]\n"
        "«Vous voulez vraiment continuer?»[end]"
    )
