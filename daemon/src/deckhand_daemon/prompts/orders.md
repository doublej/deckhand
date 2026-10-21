---
name: orders
description: The person's standing orders for one session, in front of the message they just sent.
# The most a person may put in the field, in characters. Here rather than in the code because it
# is a property of this wrapper rather than of the store: these words ride on *every* prompt, so
# their length is a price paid per turn, and the number belongs beside the sentence spending it.
# 2000 characters is roughly 500 tokens a turn — a long paragraph, and nothing like a document.
limit: 2000
---

<standing_orders from="JJ">{orders}</standing_orders>
{prompt}
