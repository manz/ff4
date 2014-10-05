# coding: utf-8
import re

text = """Cecil: Here we gow
again.
Cain:        I love
eating tea.

Rosa: Ww-hat !?


Cecil: Yeah...[end]"""


def vwf_text_format(input):
    output = re.sub(r'\s+', ' ', input)
    output = re.sub(r'((?:\.+)|(?:!\?)|(?:\?!)|(?:!)|(?:\?))\s*', '\g<1>[new]\n', output)
    output = re.sub(r'\[new\]\n\[end\]', '[end]', output)
    return output


if __name__ == '__main__':
    print(vwf_text_format(text))