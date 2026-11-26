"""Search pipelines."""


class SearchBusy(RuntimeError):
    """Another request still owns the candidate scan."""
