# Miraio

Miraio is a native client through which eligible Anime365 subscribers discover and watch the catalogue made available to them.

## Language

**Anime365 Profile**:
The identity Anime365 returns for a signed-in person, whether or not that person currently has an active Subscription.
_Avoid_: Account, user, login

**Subscriber**:
A person represented by an Anime365 Profile whose active Subscription permits Catalogue playback.
_Avoid_: User, customer, account holder

**Subscription**:
The Anime365 entitlement that determines whether a Subscriber may use protected catalogue and playback capabilities.
_Avoid_: Membership, plan, license

**Subscription Eligibility**:
The determination that an Anime365 Profile's Subscription is unknown, inactive, or active. Only an active determination makes that person a Subscriber.
_Avoid_: Premium status, membership status

**Catalogue**:
The collection of anime Series available for discovery through Anime365.
_Avoid_: Library, feed

**Series**:
A catalogue title whose playable content is organized into Episodes.
_Avoid_: Show, title

**Episode**:
A playable installment of a Series.
_Avoid_: Video, item

**Translation**:
A selectable Anime365 dub or subtitle translation belonging to one Episode.
_Avoid_: Channel, rendition, version

**Playback Session**:
One continuous attempt to play an Episode using a selected Translation.
_Avoid_: Login session, stream

**Access Token**:
The persistent secret Anime365 issues to authorize an Anime365 Profile's protected capabilities.
_Avoid_: Session, refresh token, password

**Watch History**:
Miraio's authoritative Anime365 Profile-specific record of Episodes watched and their playback progress.
_Avoid_: Activity, viewing log

**Watch History Entry**:
One Anime365 Profile's authoritative playback-progress record for one Episode, independent of the selected Translation.
_Avoid_: Playback record, Translation history

**Release Transaction**:
The version-, tag-, and commit-bound operation that carries one Miraio release through publication and verified delivery to its supported distribution channel.
_Avoid_: Release job, pipeline run

**Release Incident**:
One durable, redacted record of an unresolved failure affecting a Release Transaction.
_Avoid_: Failed run, alert

**Release Operator**:
The designated maintainer accountable for Release Incidents and Miraio's long-lived release credentials.
_Avoid_: On-call, release admin
